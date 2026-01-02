# Ti.Network.Manager - Quick Reference Card

## Installation
```javascript
const NetworkManager = require('ti.network.manager');
```

## 1 - AI Streaming (ChatGPT-style)
```javascript
const stream = NetworkManager.createStreamRequest({
    url: 'https://api.example.com/ai/chat',
    method: 'POST',
    body: JSON.stringify({ message: 'Hello!' })
});

stream.addEventListener('chunk', (e) => {
    label.text += e.data;  // Update UI in real-time
});

stream.start();
```

## 2 - Secure API Calls (Certificate Pinning)
```javascript
// Setup once
NetworkManager.setCertificatePinning('api.example.com', [
    'sha256/YOUR_CERT_HASH='
]);

// All requests to this domain now validated
```

## 3 - Auto-Add Auth Headers (Interceptors)
```javascript
// Setup once
NetworkManager.addRequestInterceptor((config) => {
    config.headers['Authorization'] = 'Bearer ' + Ti.App.Properties.getString('your_token');
    return config;
});

// All requests now have auth automatically
```

## 4 - Automatic Retry
```javascript
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/some/data',
    retry: {
        max: 5,
        backoff: NetworkManager.RETRY_BACKOFF_EXPONENTIAL,
        retryOn: [500, 502, 503, 504]
    }
});

request.send();
```

## 5 - Cache API Responses
```javascript
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/some/data',
    cache: {
        policy: NetworkManager.CACHE_POLICY_CACHE_FIRST,
        ttl: 3600  // 1 hour
    }
});

request.addEventListener('complete', (e) => {
    if (e.cached) console.log('From cache!');
});

request.send();
```

## 6 - Priority Requests
```javascript
// High priority - user-facing
const critical = NetworkManager.createRequest({
    url: 'https://api.example.com/user/data',
    priority: NetworkManager.PRIORITY_HIGH
});

// Low priority - analytics
const analytics = NetworkManager.createRequest({
    url: 'https://api.example.com/track/event',
    priority: NetworkManager.PRIORITY_LOW
});
```

## 7 - WebSocket Real-time
```javascript
const ws = NetworkManager.createWebSocket({
    url: 'wss://api.example.com/realtime/data'
});

ws.addEventListener('open', () => {
    ws.send(JSON.stringify({ action: 'subscribe' }));
});

ws.addEventListener('message', (e) => {
    const data = JSON.parse(e.data);
    updateUI(data);
});

ws.connect();
```

## 8 - Standard Request with Progress
```javascript
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/some/data',
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ data: 'value' })
});

request.addEventListener('progress', (e) => {
    const percent = (e.received / e.total) * 100;
    progressBar.value = percent;
});

request.addEventListener('complete', (e) => {
    if (e.success) {
        const data = JSON.parse(e.body);
        // Use data
    }
});

request.send();
```

## 9 - Handle Errors Globally
```javascript
NetworkManager.addResponseInterceptor((response) => {
    if (response.statusCode === 401) {
        // Token expired, refresh
        refreshAuthToken();
    } else if (response.statusCode === 503) {
        // Maintenance mode
        showMaintenanceDialog();
    }
    return response;
});
```

## 10 - Cancel Requests
```javascript
const stream = NetworkManager.createStreamRequest({...});
stream.start();

// Cancel anytime
stream.cancel();
```

## Complete Example: AI Movie Chat

```javascript
// Setup
NetworkManager.setCertificatePinning('api.example.com', ['sha256/HASH=']);
NetworkManager.addRequestInterceptor((config) => {
    config.headers['Authorization'] = 'Bearer ' + Ti.App.Properties.getString('your_token');
    return config;
});

// Create streaming request
const stream = NetworkManager.createStreamRequest({
    url: 'https://api.example.com/ai/recommend',
    method: 'POST',
    body: JSON.stringify({
        message: 'Recommend action movies like John Wick',
        stream: true
    }),
    priority: NetworkManager.PRIORITY_HIGH,
    retry: {
        max: 3,
        backoff: NetworkManager.RETRY_BACKOFF_EXPONENTIAL
    }
});

let fullResponse = '';

stream.addEventListener('chunk', (e) => {
    const chunk = JSON.parse(e.data);
    if (chunk.type === 'token') {
        fullResponse += chunk.content;
        aiLabel.text = fullResponse;  // Real-time update!
    }
});

stream.addEventListener('complete', () => {
    console.log('AI recommendation complete!');
});

stream.start();
```

## 🎨 Constants Reference

### Priority
- `NetworkManager.PRIORITY_HIGH`
- `NetworkManager.PRIORITY_NORMAL`
- `NetworkManager.PRIORITY_LOW`

### Cache Policy
- `NetworkManager.CACHE_POLICY_NETWORK_ONLY`
- `NetworkManager.CACHE_POLICY_CACHE_FIRST`
- `NetworkManager.CACHE_POLICY_NETWORK_FIRST`

### Retry Backoff
- `NetworkManager.RETRY_BACKOFF_LINEAR`
- `NetworkManager.RETRY_BACKOFF_EXPONENTIAL`

## 🔧 Utility Methods

```javascript
// Clear cache
NetworkManager.clearCache('api.example.net');  // Domain
NetworkManager.clearCache();                  // All

// Remove certificate pinning
NetworkManager.setCertificatePinning('api.example.net', []);
```

## 📱 Events Reference

### Request/Stream Events
- `chunk` - Data chunk received (streaming only)
- `progress` - Upload/download progress
- `complete` - Request completed
- `error` - Error occurred
- `cancelled` - Request cancelled

### WebSocket Events
- `open` - Connection opened
- `message` - Message received
- `binary` - Binary data received
- `pong` - Ping response
- `close` - Connection closed
- `error` - Error occurred

## 🚨 Common Patterns

### Pattern: Loading State
```javascript
const request = NetworkManager.createRequest({...});
showLoader();
request.addEventListener('complete', hideLoader);
request.addEventListener('error', hideLoader);
request.send();
```

### Pattern: Offline Support
```javascript
const request = NetworkManager.createRequest({
    url: 'https://api.example.net/movies',
    cache: {
        policy: NetworkManager.CACHE_POLICY_CACHE_FIRST,
        ttl: 86400  // 24 hours
    }
});
// Works offline if cached!
```

### Pattern: Authenticated Requests
```javascript
// Setup once at app start
NetworkManager.addRequestInterceptor((config) => {
    config.headers['Authorization'] = 'Bearer ' + Ti.App.Properties.getString('your_token');
    return config;
});

// All requests now authenticated
const request = NetworkManager.createRequest({
    url: 'https://api.example.net/user/profile'
});
request.send();
```

---

**Tip**: For AI streaming, always use `PRIORITY_HIGH` for better UX!

**Security**: Always use certificate pinning for production APIs!

**Performance**: Enable caching for static/semi-static data!

---

See [README.md](https://github.com/deckameron/Ti.Network.Manager/blob/main/README.md) for complete documentation.
