# Upstream Response Transformer Plugin

This plugin captures the response from upstream services and sends it to an external API. Based on the external API's response, it can either log the interaction or replace the upstream response entirely.

## How it Works

The plugin operates in the `access` phase and:
1. Makes the upstream call itself (instead of letting APISIX do it)
2. Captures the complete upstream response (status, headers, body)
3. Sends this response data to an external API
4. Based on the mode and external API response, either:
   - Returns the original upstream response (notify mode)
   - Returns the external API response (replace mode)

## Configuration

### Schema

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| external_api_url | string | Yes | - | URL of the external API to call |
| timeout | integer | No | 5000 | Timeout for external API call in milliseconds (1-60000) |
| forward_headers | array[string] | No | [] | Headers to forward from request/response to the external API |
| method | string | No | "POST" | HTTP method for external API call (GET, POST, PUT, PATCH) |
| mode | string | No | "notify" | Operation mode: "notify" or "replace" |
| response_headers | array[object] | No | [] | Response header configurations |

### Response Headers Configuration

Each item in `response_headers` array:

| Property | Type | Required | Default | Description |
|----------|------|----------|---------|-------------|
| name | string | Yes | - | Name of the header to set |
| mode | string | No | "replace" | Header mode: "replace", "notify", or "empty" |
| success_value | string | No | "true" | Header value on successful external API call |
| failure_value | string | No | "false" | Header value on failed external API call |

Header modes:
- **replace**: Always set the header regardless of external API result
- **notify**: Only set the header when external API call succeeds
- **empty**: Only set the header when external API call fails

## External API Request Format

The plugin sends a POST request to the external API with the following JSON body:

```json
{
  "upstream_status": 200,
  "upstream_headers": {
    "content-type": "application/json",
    "x-custom-header": "value"
  },
  "upstream_body": "{\"key\":\"value\"}",
  "request_uri": "/api/users/123",
  "request_method": "GET",
  "client_ip": "192.168.1.100",
  "timestamp": 1627890123,
  "message": "Upstream response notification from APISIX"
}
```

## Usage Examples

### Example 1: Notify Mode (Logging)

```json
{
  "plugins": {
    "upstream-response-transformer": {
      "external_api_url": "https://logger.example.com/log",
      "timeout": 10000,
      "forward_headers": ["X-Request-ID", "Authorization"],
      "mode": "notify",
      "response_headers": [
        {
          "name": "X-Logged",
          "mode": "notify",
          "success_value": "true"
        }
      ]
    }
  }
}
```

In this configuration:
- The upstream response is sent to the logging service
- The original upstream response is returned to the client
- A header `X-Logged: true` is added if logging was successful

### Example 2: Replace Mode (Response Transformation)

```json
{
  "plugins": {
    "upstream-response-transformer": {
      "external_api_url": "https://transformer.example.com/transform",
      "timeout": 5000,
      "forward_headers": ["X-User-ID"],
      "mode": "replace",
      "response_headers": [
        {
          "name": "X-Transformed",
          "mode": "replace",
          "success_value": "true",
          "failure_value": "false"
        }
      ]
    }
  }
}
```

In this configuration:
- The upstream response is sent to the transformation service
- If successful, the transformer's response replaces the upstream response
- If failed, the original upstream response is returned
- A header `X-Transformed` indicates whether transformation occurred

### Example 3: Conditional Headers

```json
{
  "plugins": {
    "upstream-response-transformer": {
      "external_api_url": "https://api.example.com/process",
      "mode": "notify",
      "response_headers": [
        {
          "name": "X-Process-Status",
          "mode": "replace",
          "success_value": "processed",
          "failure_value": "failed"
        },
        {
          "name": "X-Process-Success",
          "mode": "notify",
          "success_value": "true"
        },
        {
          "name": "X-Process-Error",
          "mode": "empty",
          "failure_value": "external-api-failed"
        }
      ]
    }
  }
}
```

This sets different headers based on the external API result:
- `X-Process-Status`: Always set (either "processed" or "failed")
- `X-Process-Success`: Only set on success
- `X-Process-Error`: Only set on failure

## Important Notes

1. **Performance Impact**: This plugin makes an additional HTTP call in the request path, which will increase latency.

2. **Timeout Handling**: Set appropriate timeouts to avoid blocking requests for too long.

3. **Error Handling**: If the external API fails in "replace" mode, the original upstream response is returned.

4. **Load Balancing**: Currently, the plugin uses the first upstream node. Advanced load balancing is not implemented.

5. **HTTPS Support**: The plugin currently only supports HTTP upstream connections. HTTPS support would require additional configuration.

## Differences from response-transformer Plugin

- **response-transformer**: Calls external API in access phase BEFORE upstream
- **upstream-response-transformer**: Calls external API AFTER receiving upstream response

Choose based on your use case:
- Use `response-transformer` for pre-processing, authentication, or request enrichment
- Use `upstream-response-transformer` for logging, post-processing, or response transformation 