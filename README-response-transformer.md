# APISIX Response Transformer Plugin

A flexible APISIX plugin that calls external APIs during request processing and provides configurable response header management.

## Overview

The `response-transformer` plugin allows you to:
- Call external APIs during the request access phase
- Configure multiple response headers with different behaviors
- Choose between notification and replacement modes
- Handle success/failure scenarios with custom header values

## Features

- ✅ **External API Integration**: Call external APIs with configurable timeouts and methods
- ✅ **Flexible Header Management**: Set multiple headers with different modes and values
- ✅ **Success/Failure Handling**: Different header behaviors based on external API results
- ✅ **Request Forwarding**: Forward specific headers to external APIs
- ✅ **Multiple Operation Modes**: Notify or replace upstream responses

## Configuration Schema

### Basic Configuration

```json
{
  "external_api_url": "https://api.example.com/endpoint",
  "timeout": 5000,
  "method": "POST",
  "mode": "notify"
}
```

### Full Configuration

```json
{
  "external_api_url": "https://api.example.com/endpoint",
  "timeout": 10000,
  "method": "POST",
  "mode": "notify",
  "forward_headers": ["Authorization", "X-Request-ID"],
  "header_config": [
    {
      "name": "X-Processing-Status",
      "mode": "replace",
      "success_value": "completed",
      "failure_value": "failed"
    },
    {
      "name": "X-External-API-Success",
      "mode": "notify",
      "success_value": "true"
    },
    {
      "name": "X-Error-Details",
      "mode": "empty",
      "failure_value": "external_api_error"
    }
  ]
}
```

## Configuration Parameters

### Core Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `external_api_url` | string | ✅ | - | URL of the external API to call |
| `timeout` | integer | ❌ | 5000 | Timeout in milliseconds (1-60000) |
| `method` | string | ❌ | "POST" | HTTP method: GET, POST, PUT, PATCH |
| `mode` | string | ❌ | "notify" | Operation mode: "notify" or "replace" |
| `forward_headers` | array | ❌ | [] | Headers to forward to external API |
| `header_config` | array | ❌ | [] | Array of header configurations |

### Header Configuration

Each header configuration object supports:

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `name` | string | ✅ | - | Name of the header to set |
| `mode` | string | ❌ | "replace" | Header mode: "replace", "notify", or "empty" |
| `success_value` | string | ❌ | "true" | Value when external API succeeds |
| `failure_value` | string | ❌ | "false" | Value when external API fails |

## Operation Modes

### Plugin Modes

- **`notify`**: Call external API and continue with upstream request
- **`replace`**: Skip upstream and return external API response

### Header Modes

- **`replace`**: Always set header (success or failure)
- **`notify`**: Only set header on successful external API calls
- **`empty`**: Only set header on failed external API calls

## Usage Examples

### 1. Basic Notification

```json
{
  "uri": "/api/users",
  "plugins": {
    "response-transformer": {
      "external_api_url": "https://analytics.example.com/track",
      "mode": "notify"
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "backend.example.com:80": 1
    }
  }
}
```

### 2. Response Replacement with Headers

```json
{
  "uri": "/api/transform",
  "plugins": {
    "response-transformer": {
      "external_api_url": "https://transform.example.com/process",
      "mode": "replace",
      "header_config": [
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

### 3. Multiple Headers with Different Modes

```json
{
  "uri": "/api/complex",
  "plugins": {
    "response-transformer": {
      "external_api_url": "https://processor.example.com/validate",
      "mode": "notify",
      "forward_headers": ["Authorization", "X-Request-ID"],
      "header_config": [
        {
          "name": "X-Validation-Status",
          "mode": "replace",
          "success_value": "validated",
          "failure_value": "validation_failed"
        },
        {
          "name": "X-Processing-Complete",
          "mode": "notify",
          "success_value": "yes"
        },
        {
          "name": "X-Error-Code",
          "mode": "empty",
          "failure_value": "EXTERNAL_API_ERROR"
        }
      ]
    }
  },
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "api.example.com:80": 1
    }
  }
}
```

## Request Data Sent to External API

The plugin sends the following data to the external API:

```json
{
  "request_uri": "/api/endpoint",
  "request_method": "POST",
  "request_headers": {
    "authorization": "Bearer token",
    "content-type": "application/json"
  },
  "request_body": "original request body",
  "client_ip": "192.168.1.100",
  "timestamp": 1704067200,
  "message": "Request notification from APISIX access phase"
}
```

## Header Behavior Examples

### Success Scenario
External API returns 200 OK:

| Header Mode | Header Set? | Value |
|-------------|-------------|-------|
| `replace` | ✅ | success_value |
| `notify` | ✅ | success_value |
| `empty` | ❌ | - |

### Failure Scenario  
External API returns non-200 or times out:

| Header Mode | Header Set? | Value |
|-------------|-------------|-------|
| `replace` | ✅ | failure_value |
| `notify` | ❌ | - |
| `empty` | ✅ | failure_value |

## Installation

1. Copy the plugin file to your APISIX plugins directory:
   ```bash
   cp response-transformer.lua /usr/local/apisix/apisix/plugins/
   ```

2. Add the plugin to your APISIX configuration (`conf/config.yaml`):
   ```yaml
   plugins:
     - response-transformer
   ```

3. Reload APISIX:
   ```bash
   apisix reload
   ```

## Testing

Use the provided test file to verify functionality:

```bash
# Basic test
curl -X GET http://localhost:9080/transform-test \
  -H "Authorization: Bearer test-token" \
  -H "X-Request-ID: test-123"
```

For comprehensive testing, see `test-response-transformer.http` file.

## Error Handling

- **External API Timeout**: Plugin continues with upstream, sets failure headers
- **External API Error**: Plugin continues with upstream (notify mode), sets failure headers
- **Network Issues**: Plugin logs error and continues with upstream

## Performance Considerations

- External API calls add latency to requests
- Use appropriate timeouts to prevent request blocking
- Consider using async external API calls for high-traffic scenarios
- Monitor external API performance and availability

## Security Notes

- Validate external API URLs to prevent SSRF attacks
- Use HTTPS for external API calls in production
- Be cautious with forwarded headers containing sensitive data
- Consider rate limiting external API calls

## Troubleshooting

### Common Issues

1. **Headers not appearing**: Check header mode configuration
2. **External API not called**: Verify URL and network connectivity
3. **Timeouts**: Adjust timeout values based on external API performance
4. **SSL issues**: Set `ssl_verify = false` for testing (not recommended for production)

### Debug Logging

The plugin logs extensively. Check APISIX error logs:

```bash
tail -f /usr/local/apisix/logs/error.log | grep response-transformer
```

## License

Licensed under the Apache License, Version 2.0. 