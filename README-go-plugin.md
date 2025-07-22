# Go Plugin Runner - Upstream Response Transformer

Bu implementasyon APISIX'in Go Plugin Runner özelliğini kullanarak upstream response transformation işlemini gerçekleştirir.

## 🎯 Avantajlar

### ✅ APISIX Native Özelliklerini Korur
- **Load Balancing**: Round-robin, weighted, least connections
- **Health Checks**: Passive/active health monitoring
- **Retry Logic**: Configurable retry policies
- **Connection Pooling**: Optimized connection management
- **SSL/TLS**: Full mTLS ve certificate management
- **Observability**: Built-in metrics ve tracing

### ✅ Response Phase İşlemleri
- **Body Filter Phase**: Upstream response'u yakalayıp değiştirebilir
- **HTTP İstekleri**: Go'da blocking HTTP calls yapabilir
- **Response Replacement**: External API response ile değiştirebilir
- **Header Management**: Conditional header setting

### ✅ Performance & Reliability
- **Separate Process**: APISIX worker'larını etkilemez
- **Go Performance**: Native HTTP client ve JSON handling
- **Error Handling**: Robust error management
- **Logging**: Structured logging

## 🏗️ Mimari

```
Client → APISIX → Upstream → Go Plugin Runner → External API
          ↓         ↓           ↓                    ↓
      Routing   Load Balance  Response Process   Transform
                Health Check  HTTP Call          
                Retry Logic   Header Setting     
```

## 🚀 Kurulum

### 1. Build ve Start
```bash
# Dependencies download
go mod download

# Build and start services
docker-compose up --build
```

### 2. Plugin Verification
```bash
# Check plugin runner logs
docker-compose logs go-plugin-runner

# Verify APISIX connection
docker-compose logs apisix | grep "ext-plugin"
```

## 📝 Configuration

### Route Configuration
```json
{
  "uri": "/api/users",
  "upstream": {
    "type": "roundrobin",
    "nodes": {
      "backend1.example.com:80": 1,
      "backend2.example.com:80": 1
    }
  },
  "plugins": {
    "ext-plugin-post-req": {
      "conf": [
        {
          "name": "upstream-response-transformer",
          "value": {
            "external_api_url": "https://analytics.company.com/track",
            "timeout": 5000,
            "forward_headers": ["X-Request-ID", "Authorization"],
            "method": "POST",
            "mode": "notify",
            "response_headers": [
              {
                "name": "X-Processed",
                "mode": "replace",
                "success_value": "true",
                "failure_value": "false"
              }
            ]
          }
        }
      ]
    }
  }
}
```

### Plugin Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| external_api_url | string | Yes | - | External API endpoint |
| timeout | int | No | 5000 | Timeout in milliseconds |
| forward_headers | []string | No | [] | Headers to forward |
| method | string | No | "POST" | HTTP method |
| mode | string | No | "notify" | "notify" or "replace" |
| response_headers | []object | No | [] | Response header configs |

## 🔄 Operation Modes

### Notify Mode
- **Purpose**: Logging, analytics, monitoring
- **Behavior**: Keep original upstream response
- **External API**: Fire-and-forget
- **Performance**: Minimal impact

### Replace Mode  
- **Purpose**: Response transformation, enrichment
- **Behavior**: Replace upstream response with external API response
- **External API**: Blocking call
- **Performance**: Dependent on external API latency

## 📊 External API Payload

```json
{
  "upstream_status": 200,
  "upstream_headers": {
    "content-type": ["application/json"],
    "x-custom": ["value"]
  },
  "upstream_body": "{\"id\":123,\"name\":\"user\"}",
  "request_uri": "/api/users/123",
  "request_method": "GET",
  "client_ip": "192.168.1.100",
  "timestamp": 1627890123,
  "message": "Upstream response notification from APISIX Go Plugin"
}
```

## 🧪 Testing

### 1. Test Notify Mode
```bash
# Create route
curl -X POST http://localhost:9180/apisix/admin/routes/1 \
  -H "X-API-KEY: edd1c9f034335f136f87ad84b625c8f1" \
  -H "Content-Type: application/json" \
  -d @test-go-upstream-response-transformer.http

# Test request
curl http://localhost:9080/test-go-upstream-notify/get \
  -H "User-Agent: TestClient/1.0"
```

### 2. Monitor Logs
```bash
# Plugin runner logs
docker-compose logs -f go-plugin-runner

# APISIX logs
docker-compose logs -f apisix
```

## 🔍 Debugging

### Common Issues

1. **Plugin Not Loading**
   ```bash
   # Check ext-plugin configuration
   grep "ext-plugin" config/config.yaml
   
   # Verify socket connection
   ls -la /tmp/runner.sock
   ```

2. **HTTP Call Failures**
   ```bash
   # Check external API connectivity
   docker-compose exec go-plugin-runner ping external-api.com
   
   # Review timeout settings
   ```

3. **Response Issues**
   ```bash
   # Monitor request/response flow
   docker-compose logs apisix | grep upstream-response-transformer
   ```

## 🔧 Development

### Modify Plugin
```bash
# Edit plugin code
vim plugins/upstream_response_transformer.go

# Rebuild
docker-compose build go-plugin-runner

# Restart
docker-compose restart go-plugin-runner
```

### Add Features
- **Authentication**: Add API key support
- **Caching**: Response caching mechanism  
- **Filtering**: Conditional processing rules
- **Metrics**: Custom metric collection

## 🚦 Production Considerations

### Security
- **API Keys**: Secure external API authentication
- **SSL/TLS**: HTTPS external API calls
- **Input Validation**: Robust payload validation

### Performance
- **Timeout Tuning**: Appropriate timeout values
- **Connection Pooling**: HTTP client optimization
- **Circuit Breaker**: External API failure handling

### Monitoring
- **Health Checks**: Plugin runner health
- **Metrics**: Success/failure rates
- **Alerting**: External API errors

## 📚 Reference

- [APISIX Go Plugin Runner](https://github.com/apache/apisix-go-plugin-runner)
- [APISIX External Plugin](https://apisix.apache.org/docs/apisix/external-plugin/)
- [Go Plugin Development](https://apisix.apache.org/docs/apisix/plugin-develop/) 