# APISIX Plugin Development Environment

This directory provides a Docker Compose setup for developing and testing custom APISIX Lua plugins.

## Directory Structure

```
.
├── config/
│   ├── config.yaml           # Custom APISIX configuration (loads plugins, connects to etcd)
│   └── dashboard-config.yaml  # Configuration for the APISIX Dashboard
├── docker-compose.yml        # Docker Compose definition for APISIX, etcd, Dashboard, and Redpanda
├── Makefile                  # Convenience commands for managing the environment
├── plugins/
│   └── hello-world.lua       # Example custom Lua plugin
├── test.http                 # HTTP request examples for testing plugins
└── README.md                 # This file
```

## Prerequisites

-   Docker
-   Docker Compose

## Usage

1.  **Place your custom Lua plugin(s)** inside the `plugins/` directory.
    -   Make sure your plugin file name matches the plugin name (e.g., `my-plugin.lua` for a plugin named `my-plugin`).
    -   Remember to update `config/config.yaml` to include your new plugin name in the `plugins:` list.

2.  **Start the environment:**
    ```bash
    docker compose up -d
    ```
    or using the Makefile:
    ```bash
    make up
    ```
    This will start APISIX, etcd, APISIX Dashboard, and Redpanda containers in the background.
    -   APISIX will be accessible on `http://localhost:9080` (proxy) and `http://localhost:9180` (Admin API).
    -   The APISIX Dashboard will be available at `http://localhost:9000`.

    *go-plugin-runner* build:
    `docker-compose up --build go-plugin-runner -d`

3.  **Test your plugin with path rewriting:**
    -   Use the APISIX Admin API to create a route that combines the hello-world plugin with the proxy-rewrite plugin:

      ```bash
      curl -i "http://127.0.0.1:9180/apisix/admin/routes/3" -H 'X-API-KEY: edd1c9f034335f136f87ad84b625c8f1' -X PUT -d '\
      {
        "uri": "/api/get",
        "plugins": {
          "hello-world": {
            "message": "Hello from rewritten path!"
          },
          "proxy-rewrite": {
            "uri": "/get"
          }
        },
        "upstream": {
          "type": "roundrobin",
          "nodes": {
            "httpbin.org:80": 1
          }
        }
      }'
      ```
      *(Note: The default Admin API key `edd1c9f034335f136f87ad84b625c8f1` is used here. **Change this in a production environment!** You can configure it in `config/config.yaml`)*

    -   Send a request to the route:
      ```bash
      curl -i http://127.0.0.1:9080/api/get
      ```
      You should see a successful 200 response with the custom header `X-Hello-World: Hello from rewritten path!` added by your plugin.
      
    -   For convenience, you can use the included `test.http` file with a REST client (like the VS Code REST Client extension) to test your route, or run `make create-route` followed by `make test-api`.

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

-   The `config/config.yaml` file mounts your local configuration into the container. Changes require restarting or reloading APISIX.
-   The `plugins/` directory is mounted read-only into the container. After changing plugin code, run `make reload`.
-   The hello-world plugin adds an `X-Hello-World` header to all responses. You can customize the header value by setting the `message` parameter in the plugin configuration.
-   The path rewriting example demonstrates how to combine multiple plugins:
    - The `hello-world` plugin adds a custom header to the response
    - The `proxy-rewrite` plugin changes the request path from `/api/get` to `/get` before forwarding to the upstream
-   You can create the route and test it using the commands in the Makefile: `make create-route` and `make test-api`.