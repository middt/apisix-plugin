# APISIX Plugin Development Environment

This directory provides a Docker Compose setup for developing and testing custom APISIX Lua plugins.

## Directory Structure

```
.
├── conf/
│   └── config.yaml       # Custom APISIX configuration (loads plugins, connects to etcd)
├── docker-compose.yml    # Docker Compose definition for APISIX and etcd
├── Makefile              # Convenience commands for managing the environment
├── plugins/
│   └── hello-world.lua   # <<< Place your custom Lua plugins here
└── README.md             # This file
```

## Prerequisites

-   Docker
-   Docker Compose

## Usage

1.  **Place your custom Lua plugin(s)** inside the `plugins/` directory.
    -   Make sure your plugin file name matches the plugin name (e.g., `my-plugin.lua` for a plugin named `my-plugin`).
    -   Remember to update `conf/config.yaml` to include your new plugin name in the `plugins:` list.

2.  **Start the environment:**
    ```bash
    make up
    ```
    This will start APISIX and etcd containers in the background.
    -   APISIX will be accessible on `http://localhost:9080` (proxy) and `http://localhost:9090` (control API).
    -   The APISIX Dashboard will be available at `http://localhost:9000`.

3.  **Test your plugin:**
    -   Use the APISIX Admin API (or the Dashboard) to create a route and enable your custom plugin on it.
    -   Example using `curl` to create a route for `http://httpbin.org/get` with the `hello-world` plugin enabled:

      ```bash
      curl -i "http://127.0.0.1:9090/apisix/admin/routes/1" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '\
      {
        "uri": "/test",
        "plugins": {
          "hello-world": {}
        },
        "upstream": {
          "type": "roundrobin",
          "nodes": {
            "httpbin.org:80": 1
          }
        }
      }'
      ```
      *(Note: The default Admin API key `edd1c9f034335f136f87ad84b625c8f1` is used here. **Change this in a production environment!** You can configure it in `conf/config.yaml`)*

    -   Send a request to the route:
      ```bash
      curl http://127.0.0.1:9080/test
      ```
      You should see the effects of your plugin (e.g., the `X-Hello-World` header added by the example plugin).

4.  **Develop and Reload:**
    -   Modify your plugin code in the `plugins/` directory.
    -   Reload the APISIX configuration to apply changes:
        ```bash
        make reload
        ```
    -   Test again.

5.  **View Logs:**
    ```bash
    make logs-apisix  # View APISIX logs
    make logs-etcd    # View etcd logs
    ```

6.  **Stop the environment:**
    ```bash
    make down
    ```

7.  **Stop and remove data volumes (for a clean start):**
    ```bash
    make clean
    ```

## Notes

-   The `conf/config.yaml` file mounts your local configuration into the container. Changes require restarting or reloading APISIX.
-   The `plugins/` directory is mounted read-only into the container. After changing plugin code, run `make reload`. 