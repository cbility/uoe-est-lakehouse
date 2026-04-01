# UoE Estates Lakehouse

This project initialises all services required to run a local data lakehouse with [DuckLake](https://ducklake.select/). It provisions containerised services for S3-compatible object storage, a PostgreSQL metadata catalogue, and secure remote access.

## Project Structure

```
.
├── docker-compose.yml
├── README.md
└── init/
    ├── Dockerfile.garage-init
    └── scripts/
        ├── backup/
        │   ├── backup.sh          # pg_dump script for catalog backups
        │   └── entrypoint.sh      # configures and schedules backup
        ├── garage/
        │   ├── garage-config.sh   # Generates garage.toml configuration
        │   └── garage-init.sh     # Provisions node, bucket, key
        └── postgres/
            └── 00-pg_hba.sh       # Allows connection to catalog database
```


## Architecture

```
            ┌────────────────────────────┐
            │          DuckLake          │
            │                            │
            │  ┌──────────────────────┐  │
            │  │  Catalogue           │  │
            │  │  PostgreSQL          │  │
            │  └──────────────────────┘  │
            │                            │
            │  ┌──────────────────────┐  │
            │  │  Data Storage        │  │
            │  │  Garage (S3)         │  │
            │  └──────────────────────┘  │
            └─────────────┬──────────────┘
                          │  (via Netbird)
           ┌──────────────┴────────────┐
  ┌────────┴────────┐         ┌────────┴────────┐
  │   DuckDB Client │         │   DuckDB Client │
  │   (remote)      │         │   (remote)      │
  └─────────────────┘         └─────────────────┘
  
```

| Service | Image | Role |
|---|---|---|
| `garage` | `dxflrs/garage:v2.2.0` | S3-compatible object storage |
| `postgres` | `postgres:17` | DuckLake metadata catalogue |
| `netbird-client` | `netbirdio/netbird:latest` | Secure remote access |
| `garage-config` | `alpine` | Init: generates `garage.toml` from env vars |
| `garage-init` | Custom | Init: configures Garage node, bucket, and S3 key |
| `postgres-backup` | `alpine` | Nightly PostgreSQL dump at 03:00 UTC |

> **Note:** The container network MTU is set to `1100` to ensure database connectivity on the UoE network.

## Use

### Prerequisites

- Containerisation platform - [Podman](https://podman.io/docs/installation) (recommended, with Docker compatibility enabled) or [Docker](https://docs.docker.com/engine/install/)
- A Netbird  account and [setup key](https://app.netbird.io/setup-keys) 

---

### Configuration

Copy or create a `.env` file in the project root with the following variables:

```env
# Netbird
NB_SETUP_KEY=<your-netbird-setup-key>

# Garage (S3 storage)
GARAGE_RPC_SECRET=<64-char hex secret>   # openssl rand -hex 32
GARAGE_ADMIN_TOKEN=<random token>
S3_REGION=garage
S3_BUCKET=uoe-est-lake

# PostgreSQL
POSTGRES_USER=admin
POSTGRES_PASSWORD=<strong password>
POSTGRES_DB=uoe_est_lake_catalog
POSTGRES_PORT=<port number>

# Host path for persistent data (garage data, backups)
DATA_PATH=/path/to/data
# storage capacity for configuring garage. Note that in the current single node setup this will not affect operation
HOST_STORAGE_CAPACITY_GB=<storage capacity at DATA_PATH>
```

---

### Running Services

1. **Configuration**

    Ensure the `.env` file is configured as above, and either Podman or DOcker is installed. If using Podman, ensure that Docker compatibility is enabled

2. **Start all services**

   ```bash
   docker-compose up -d
   ```

   On first run, `garage-config` and `garage-init` will run automatically to configure Garage, create the S3 key, and provision the bucket. 

3. **Retrieve Garage Credentials**

    Check the logs for the `ducklake-garage-init` container. During container intialisation the `S3_ACCESS_KEY` and `S3_SECRET_KEY` are logged. You need this information to attach to the ducklake.

> **Note:** The garage key and secret are also saved to a container volume `uoe-est-lake_garage-keys`.
### Connecting

Once the services are running you can connect to a ducklake storing metadata in the catalog database and data on disk at the specified `DATA_PATH`.

**You can connect from the machine that is hosting the ducklake, or from a remote machine.**

1. **Prerequisites**
    
    Ensure [duckDB](https://duckdb.org/install/) and [Netbird](https://app.netbird.io/install) are installed locally, and connections are permitted from the local machine to the host machine in the [Netbird Dashboard](https://app.netbird.io/access-control).
2. **Create duckDB secrets**
    
    You can attach to the ducklake from anywhere that duckDB can run. It's recommended to create [persistent secrets](https://duckdb.org/docs/current/configuration/secrets_manager#persistent-secrets) to simplify the process of attaching in future.

    ```sql 
    -- run in duckDB shell

    CREATE OR REPLACE PERSISTENT SECRET ducklake_catalog ( TYPE postgres, dbname 'uoe_est_lake_catalog', host '<NETBIRD_HOST_IP>', port <POSTGRES_PORT>, user 'admin', password '<POSTGRES_PASSWORD>');

    CREATE OR REPLACE PERSISTENT SECRET (TYPE s3, ENDPOINT '<NETBIRD_HOST_IP>:3900', URL_STYLE 'path', PROVIDER config,  KEY_ID '<S3_ACCESS_KEY>', USE_SSL 'false', SECRET '<S3_SECRET_KEY>', REGION 'garage');

    CREATE OR REPLACE PERSISTENT SECRET (TYPE ducklake, METADATA_PATH '', DATA_PATH 's3://uoe-est-lake/', METADATA_PARAMETERS MAP {'TYPE': 'postgres', 'SECRET': 'ducklake_catalog'});

    ```
3. **Attach to ducklake**

    After the persistent secrets are set, attaching to the ducklake is straightforward:
    ```sql
    -- run in duckDB shell

    ATTACH OR REPLACE 'ducklake:';
    ```
> **Note:** It is recommended to attach to the ducklake from a transient in-memory duckdb instance. This is the default behaviour when you run `duckdb`.



## Backups

The `postgres-backup` service runs a `pg_dump` every day at **03:00 UTC** and writes a single rolling backup to:

```
$DATA_PATH/backups/uoe_est_lake_catalog.backup.sql
```

The backup is written atomically (to a `.tmp` file first, then renamed). It does not sync offsite automatically — you should configure external storage sync (using e.g. onedrive) for effective backups in case of disaster.

---

## Init Container Details

### `garage-config`

Generates `/config/garage.toml` from environment variables before Garage starts. Uses a single-node layout (`replication_factor = 1`) with SQLite as the metadata engine.

### `garage-init`

Waits for Garage to become ready, then:
1. Assigns a layout to the detected node (zone `dc1`, capacity `HOST_STORAGE_CAPACITY_GB`)
2. Creates (or retrieves) an S3 key named `ducklake-key`
3. Creates the configured bucket and grants the key full access
4. Writes `S3_ACCESS_KEY` and `S3_SECRET_KEY` to the `garage-keys` volume, and logs to console

> **Note:** The `garage-init` container stays running after setup (`sleep infinity`) to allow Garage CLI access (the garage container itself does not include a shell). You can stop the container if it is not required.

---

