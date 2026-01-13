# Ti.Network.Manager

> Advanced HTTP networking module for Titanium SDK with powerful features designed for modern mobile applications.

Ti.Network.Manager is a comprehensive networking solution that extends Titanium's capabilities with advanced features like Server-Sent Events streaming, certificate pinning, automatic retry logic, sophisticated caching, and more.

![Titanium](https://img.shields.io/badge/Titanium-13.0+-red.svg) ![Platform](https://img.shields.io/badge/platform-iOS-lightgrey.svg) ![License](https://img.shields.io/badge/license-MIT-blue.svg) ![Maintained](https://img.shields.io/badge/Maintained-Yes-green.svg)

---

### Roadmap

- [x] Core 10 features for iOS
- [x] Android support
- [ ] Upload/download queuing system


## Features

Ti.Network.Manager provides everything missing from Titanium's built-in HTTP client:

1. **Streaming Responses (SSE)** - Real-time AI responses like ChatGPT
2. **Certificate Pinning** - Prevent man-in-the-middle attacks
3. **Request/Response Interceptors** - Global middleware for auth, logging
4. **Automatic Retry with Backoff** - Handle flaky networks intelligently
5. **Advanced Caching** - Multiple strategies (cache-first, network-first)
6. **Background Transfers** - Downloads that continue when app is backgrounded
7. **Request Prioritization** - QoS levels for critical vs. background requests
8. **Multipart Upload Progress** - Real-time upload progress tracking
9. **HTTP/2 & HTTP/3** - Automatic protocol negotiation for better performance
10. **WebSocket Support** - Bidirectional real-time communication

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Features](#features)
  - [Feature 1: Streaming Responses (SSE)](#feature-1-streaming-responses-sse)
  - [Feature 2: Certificate Pinning](#feature-2-certificate-pinning)
  - [Feature 3: Request/Response Interceptors](#feature-3-requestresponse-interceptors)
  - [Feature 4: Automatic Retry with Backoff](#feature-4-automatic-retry-with-backoff)
  - [Feature 5: Advanced Caching](#feature-5-advanced-caching)
  - [Feature 6: Background Transfers](#feature-6-background-transfers)
  - [Feature 7: Request Prioritization](#feature-7-request-prioritization)
  - [Feature 8: Multipart Upload Progress](#feature-8-multipart-upload-progress)
  - [Feature 9: HTTP/2 & HTTP/3 Support](#feature-9-http2--http3-support)
  - [Feature 10: WebSocket Support](#feature-10-websocket-support)
- [API Reference](#api-reference)
- [License](#license)

---

## Installation

### 1. Download the Module

Download the latest version from the [releases page](https://github.com/deckameron/Ti.Network.Manager/releases).


### 2. Install the module in your Titanium project

```bash
# Copy the compiled module to:
{YOUR_PROJECT}/modules/iphone/
```

### 3. Configure tiapp.xml

Add the module to your `tiapp.xml`:

```xml
<modules>
    <module platform="iphone">ti.network.manager</module>
</modules>
```

---

## Quick Start

Initialize the module once at the start of your application:

```javascript
const NetworkManager = require('ti.network.manager');

// Create a simple request
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/users',
    method: 'GET'
});

request.addEventListener('complete', (e) => {
    if (e.success) {
        const users = JSON.parse(e.body);
        console.log('Users:', users);
    }
});

request.send();
```

---

## Features

### Feature 1: Streaming Responses (SSE)

**Server-Sent Events (SSE) streaming for real-time data delivery.** Perfect for AI chatbots, live updates, and progressive data loading.

#### Basic Streaming Example

```javascript
const NetworkManager = require('ti.network.manager');

const stream = NetworkManager.createStreamRequest({
    url: 'https://api.example.com/ai/chat',
    method: 'POST',
    headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer YOUR_TOKEN'
    },
    body: JSON.stringify({
        message: 'Tell me about Titanium SDK',
        stream: true
    })
});

// Receive chunks as they arrive
stream.addEventListener('chunk', (e) => {
    console.log('Received chunk:', e.data);
    // Update UI progressively
    chatTextArea.value += e.data;
});

stream.addEventListener('complete', (e) => {
    console.log('Stream complete');
    console.log('Status:', e.statusCode);
});

stream.addEventListener('error', (e) => {
    console.error('Stream error:', e.error);
});

stream.start();
```

#### Advanced Streaming with Progress

```javascript
const NetworkManager = require('ti.network.manager');

let chunkCount = 0;
let totalBytes = 0;

const stream = NetworkManager.createStreamRequest({
    url: 'https://api.example.com/data/stream',
    method: 'GET',
    priority: NetworkManager.PRIORITY_HIGH
});

stream.addEventListener('chunk', (e) => {
    chunkCount++;
    totalBytes += e.data.length;
    
    console.log('Chunk #' + chunkCount + ' (' + e.data.length + ' bytes)');
    console.log('Total received: ' + totalBytes + ' bytes');
    
    // Process chunk
    processData(e.data);
});

stream.addEventListener('complete', (e) => {
    console.log('Received ' + chunkCount + ' chunks');
    console.log('Total: ' + totalBytes + ' bytes');
});

stream.start();

// Cancel streaming if needed
setTimeout(() => {
    stream.cancel();
}, 30000); // Cancel after 30 seconds
```

#### Use Cases

1. **AI Chatbots** - Stream responses from AI services like OpenAI, Anthropic, or Google Gemini for real-time user feedback.
2. **Live News Feeds** - Receive breaking news updates as they happen without polling.
3. **Stock Market Data** - Stream real-time stock prices and trading information.
4. **IoT Device Monitoring** - Monitor sensor data from connected devices in real-time.
5. **Live Event Coverage** - Stream sports scores, election results, or event updates as they occur.

---

### Feature 2: Certificate Pinning

**Secure your API connections by validating server certificates against known public key hashes.** Prevents man-in-the-middle attacks.

#### Configure Certificate Pinning

```javascript
const NetworkManager = require('ti.network.manager');

// Set certificate pins for your domain
NetworkManager.setCertificatePinning(
    'api.example.com',
    [
        'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB='
    ]
);

// Now all requests to api.example.com will validate certificates
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/secure/data',
    method: 'GET'
});

request.addEventListener('complete', (e) => {
    if (e.success) {
        console.log('Secure connection validated!');
    }
});

request.addEventListener('error', (e) => {
    console.error('Certificate validation failed:', e.error);
});

request.send();
```

#### Multiple Domains

```javascript
const NetworkManager = require('ti.network.manager');

// Pin multiple domains
NetworkManager.setCertificatePinning(
    'api.example.com',
    ['sha256/HASH1=', 'sha256/HASH2=']
);

NetworkManager.setCertificatePinning(
    'cdn.example.com',
    ['sha256/HASH3=', 'sha256/HASH4=']
);

// Requests to both domains will be pinned
```

#### How to Get Certificate Hashes

Use OpenSSL to extract the public key hash:

```bash
# Get certificate hash for your domain
openssl s_client -servername api.example.com -connect api.example.com:443 < /dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform der \
  | openssl dgst -sha256 -binary \
  | openssl enc -base64
```

#### Use Cases

1. **Banking Apps** - Ensure all financial transactions are secure and validated.
2. **Healthcare Applications** - Protect sensitive patient data with certificate validation.
3. **E-commerce** - Secure payment processing and user account information.
4. **Enterprise Apps** - Validate connections to corporate servers and prevent data breaches.
5. **Government Applications** - Meet compliance requirements for secure communications.

---

### Feature 3: Request/Response Interceptors

**Global middleware for modifying requests and responses.** Perfect for adding authentication, logging, and error handling.

#### Request Interceptor

```javascript
const NetworkManager = require('ti.network.manager');

// Add global request interceptor
NetworkManager.addRequestInterceptor((config) => {
    console.log('Intercepting request to:', config.url);
    
    // Add authentication token to all requests
    config.headers = config.headers || {};
    config.headers['Authorization'] = 'Bearer ' + getAuthToken();
    
    // Add timestamp
    config.headers['X-Request-Time'] = new Date().toISOString();
    
    // Log request
    console.log('Request:', config.method, config.url);
    
    return config;
});

// Now all requests will have the auth token
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/protected/data',
    method: 'GET'
});

request.send();
```

#### Response Interceptor

```javascript
const NetworkManager = require('ti.network.manager');

// Add global response interceptor
NetworkManager.addResponseInterceptor((response) => {
    console.log('Response status:', response.statusCode);
    
    // Handle authentication errors globally
    if (response.statusCode === 401) {
        console.log('Unauthorized - refreshing token');
        refreshAuthToken();
    }
    
    // Handle rate limiting
    if (response.statusCode === 429) {
        console.log('Rate limited - backing off');
        showRateLimitWarning();
    }
    
    // Log response
    console.log('Response received from:', response.headers);
    
    return response;
});
```

#### Combined Example

```javascript
const NetworkManager = require('ti.network.manager');

// Request interceptor - Add auth and logging
NetworkManager.addRequestInterceptor((config) => {
    config.headers = config.headers || {};
    config.headers['Authorization'] = 'Bearer ' + Ti.App.Properties.getString('authToken');
    config.headers['X-App-Version'] = Ti.App.version;
    config.headers['X-Device-ID'] = Ti.Platform.id;
    
    logAnalytics('api_request', {
        url: config.url,
        method: config.method
    });
    
    return config;
});

// Response interceptor - Handle errors globally
NetworkManager.addResponseInterceptor((response) => {
    // Handle token expiration
    if (response.statusCode === 401) {
        Ti.App.fireEvent('auth:expired');
        redirectToLogin();
    }
    
    // Handle server errors
    if (response.statusCode >= 500) {
        showErrorNotification('Server error. Please try again.');
    }
    
    // Log response time
    if (response.headers['X-Response-Time']) {
        logAnalytics('api_response_time', {
            time: response.headers['X-Response-Time']
        });
    }
    
    return response;
});
```

#### Use Cases

1. **Authentication Management** - Automatically add and refresh authentication tokens for all requests.
2. **Analytics Tracking** - Log all API calls for monitoring and debugging.
3. **Error Handling** - Implement global error handling and user notifications.
4. **API Versioning** - Add version headers to all requests automatically.
5. **Request Logging** - Debug production issues by logging all network activity.

---

### Feature 4: Automatic Retry with Backoff

**Automatically retry failed requests with configurable backoff strategies.** Handles network instability gracefully.

#### Basic Retry Configuration

```javascript
const NetworkManager = require('ti.network.manager');

const request = NetworkManager.createRequest({
    url: 'https://api.example.com/data',
    method: 'GET',
    retry: {
        max: 5,                    // Maximum 5 retry attempts
        backoff: NetworkManager.RETRY_BACKOFF_EXPONENTIAL,
        baseDelay: 1.0,           // Start with 1 second delay
        retryOn: [500, 502, 503, 504]  // Retry on server errors
    }
});

request.addEventListener('error', (e) => {
    if (e.willRetry) {
        console.log('Request failed, will retry automatically');
    } else {
        console.log('Request failed after all retries');
    }
});

request.addEventListener('complete', (e) => {
    console.log('Request succeeded!');
});

request.send();
```

#### Exponential Backoff

```javascript
const NetworkManager = require('ti.network.manager');

// Exponential backoff: 1s, 2s, 4s, 8s, 16s
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/upload',
    method: 'POST',
    body: JSON.stringify({ data: 'important' }),
    retry: {
        max: 5,
        backoff: NetworkManager.RETRY_BACKOFF_EXPONENTIAL,
        baseDelay: 1.0,
        retryOn: [408, 500, 502, 503, 504]  // Timeout and server errors
    }
});

request.send();
```

#### Linear Backoff

```javascript
const NetworkManager = require('ti.network.manager');

// Linear backoff: 2s, 4s, 6s, 8s, 10s
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/process',
    method: 'POST',
    retry: {
        max: 5,
        backoff: NetworkManager.RETRY_BACKOFF_LINEAR,
        baseDelay: 2.0,
        retryOn: [429, 500, 503]  // Rate limiting and server errors
    }
});

request.addEventListener('error', (e) => {
    console.log('Error:', e.error);
    console.log('Will retry:', e.willRetry);
});

request.send();
```

#### Custom Retry Conditions

```javascript
const NetworkManager = require('ti.network.manager');

const request = NetworkManager.createRequest({
    url: 'https://api.example.com/critical',
    method: 'POST',
    retry: {
        max: 10,  // More retries for critical operations
        backoff: NetworkManager.RETRY_BACKOFF_EXPONENTIAL,
        baseDelay: 0.5,  // Start with shorter delay
        retryOn: [408, 429, 500, 502, 503, 504, 509]  // Extensive retry conditions
    }
});

request.send();
```

#### Use Cases

1. **Unstable Networks** - Handle poor connectivity in mobile apps gracefully without user intervention.
2. **Critical Transactions** - Ensure important operations like payments complete successfully.
3. **API Rate Limiting** - Automatically retry when hitting rate limits with appropriate delays.
4. **Server Maintenance** - Retry during brief server downtime or deployments.
5. **Background Sync** - Reliably sync data even with intermittent connectivity.

---

### Feature 5: Advanced Caching

**Intelligent HTTP caching with multiple strategies and TTL support.** Reduce API calls and improve performance.

#### Cache-First Strategy

```javascript
const NetworkManager = require('ti.network.manager');

// Use cached data if available, otherwise fetch from network
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/movies',
    method: 'GET',
    cache: {
        policy: NetworkManager.CACHE_POLICY_CACHE_FIRST,
        ttl: 3600  // Cache for 1 hour (in seconds)
    }
});

request.addEventListener('complete', (e) => {
    if (e.cached) {
        console.log('Data loaded from cache');
    } else {
        console.log('Data fetched from network');
    }
    
    const movies = JSON.parse(e.body);
    displayMovies(movies);
});

request.send();
```

#### Network-First Strategy

```javascript
const NetworkManager = require('ti.network.manager');

// Try network first, fallback to cache if network fails
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/news',
    method: 'GET',
    cache: {
        policy: NetworkManager.CACHE_POLICY_NETWORK_FIRST,
        ttl: 1800  // Cache for 30 minutes
    }
});

request.send();
```

#### Network-Only (No Cache)

```javascript
const NetworkManager = require('ti.network.manager');

// Always fetch from network, never use cache
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/realtime-data',
    method: 'GET',
    cache: {
        policy: NetworkManager.CACHE_POLICY_NETWORK_ONLY
    }
});

request.send();
```

#### Clear Cache

```javascript
const NetworkManager = require('ti.network.manager');

// Clear cache for specific domain
NetworkManager.clearCache('api.example.com');

// Or clear all cache
NetworkManager.clearCache();
```

#### Complete Caching Example

```javascript
const NetworkManager = require('ti.network.manager');

// Product catalog with 1-hour cache
const productsRequest = NetworkManager.createRequest({
    url: 'https://api.example.com/products',
    method: 'GET',
    cache: {
        policy: NetworkManager.CACHE_POLICY_CACHE_FIRST,
        ttl: 3600
    }
});

productsRequest.addEventListener('complete', (e) => {
    const products = JSON.parse(e.body);
    
    if (e.cached) {
        console.log('Loaded ' + products.length + ' products from cache');
        showOfflineIndicator();
    } else {
        console.log('Fetched ' + products.length + ' products from network');
    }
    
    renderProductList(products);
});

productsRequest.send();

// Clear cache when user explicitly refreshes
refreshButton.addEventListener('click', () => {
    NetworkManager.clearCache('api.example.com');
    productsRequest.send();
});
```

#### Use Cases

1. **Product Catalogs** - Cache product listings to reduce API calls and improve browsing speed.
2. **News Articles** - Cache articles for offline reading and faster load times.
3. **User Profiles** - Cache profile data to reduce server load and improve responsiveness.
4. **Static Content** - Cache configuration, translations, and other static data.
5. **Offline Support** - Provide functionality even when network is unavailable.

---

### Feature 6: Background Transfers

**Upload and download files in the background, even when app is suspended.** Includes pause/resume support.

#### Background Download

```javascript
const NetworkManager = require('ti.network.manager');

const download = NetworkManager.createBackgroundTransfer({
    type: 'download',
    url: 'https://api.example.com/files/movie-trailer.mp4',
    destination: Ti.Filesystem.applicationDataDirectory + 'trailer.mp4',
    headers: {
        'Authorization': 'Bearer ' + getAuthToken()
    }
});

download.addEventListener('progress', (e) => {
    const percent = (e.sent / e.total * 100).toFixed(1);
    console.log('Download progress: ' + percent + '%');
    progressBar.value = percent;
    statusLabel.text = 'Downloading: ' + percent + '%';
});

download.addEventListener('complete', (e) => {
    console.log('Download complete!');
    console.log('File saved to:', e.path);
    playVideo(e.path);
});

download.addEventListener('error', (e) => {
    console.error('Download failed:', e.error);
});

download.start();
```

#### Background Upload

```javascript
const NetworkManager = require('ti.network.manager');

const videoFile = Ti.Filesystem.getFile(
    Ti.Filesystem.applicationDataDirectory,
    'recorded-video.mp4'
);

const upload = NetworkManager.createBackgroundTransfer({
    type: 'upload',
    url: 'https://api.example.com/videos/upload',
    file: videoFile.nativePath,
    headers: {
        'Authorization': 'Bearer ' + getAuthToken(),
        'Content-Type': 'video/mp4'
    }
});

upload.addEventListener('progress', (e) => {
    const percent = (e.sent / e.total * 100).toFixed(1);
    console.log('Upload progress: ' + percent + '%');
    uploadProgress.value = percent;
});

upload.addEventListener('complete', (e) => {
    console.log('Upload complete!');
    console.log('Response:', e.response);
    showSuccessMessage('Video uploaded successfully!');
});

upload.start();
```

#### Pause and Resume

```javascript
const NetworkManager = require('ti.network.manager');

const download = NetworkManager.createBackgroundTransfer({
    type: 'download',
    url: 'https://api.example.com/files/large-file.zip',
    destination: Ti.Filesystem.applicationDataDirectory + 'download.zip'
});

download.addEventListener('progress', (e) => {
    progressBar.value = (e.sent / e.total) * 100;
});

// Start download
download.start();

// Pause download
pauseButton.addEventListener('click', () => {
    download.pause();
    pauseButton.title = 'Resume';
});

// Resume download
pauseButton.addEventListener('click', () => {
    download.resume();
    pauseButton.title = 'Pause';
});

// Cancel download
cancelButton.addEventListener('click', () => {
    download.cancel();
});
```

#### Download with Retry

```javascript
const NetworkManager = require('ti.network.manager');

const download = NetworkManager.createBackgroundTransfer({
    type: 'download',
    url: 'https://api.example.com/files/document.pdf',
    destination: Ti.Filesystem.applicationDataDirectory + 'document.pdf'
});

let retryCount = 0;

download.addEventListener('error', (e) => {
    if (retryCount < 3) {
        retryCount++;
        console.log('Download failed, retrying... (' + retryCount + '/3)');
        setTimeout(() => {
            download.start();
        }, 2000);
    } else {
        console.error('Download failed after 3 retries');
        showErrorDialog('Download failed. Please try again later.');
    }
});

download.start();
```

#### Use Cases

1. **Video Downloads** - Download movie trailers, TV episodes, or user-generated content for offline viewing.
2. **Document Sync** - Sync large documents or PDFs in the background without blocking the UI.
3. **Photo Uploads** - Upload photos and videos to cloud storage without keeping app in foreground.
4. **App Updates** - Download app content updates in the background.
5. **Podcast Downloads** - Download podcast episodes for offline listening.

---

### Feature 7: Request Prioritization

**Control which requests get network resources first.** Ensure critical operations complete quickly.

#### Priority Levels

```javascript
const NetworkManager = require('ti.network.manager');

// High priority - Critical user action
const loginRequest = NetworkManager.createRequest({
    url: 'https://api.example.com/auth/login',
    method: 'POST',
    body: JSON.stringify({
        email: email,
        password: password
    }),
    priority: NetworkManager.PRIORITY_HIGH
});

// Normal priority - Standard data fetch
const dataRequest = NetworkManager.createRequest({
    url: 'https://api.example.com/data',
    method: 'GET',
    priority: NetworkManager.PRIORITY_NORMAL
});

// Low priority - Background prefetch
const prefetchRequest = NetworkManager.createRequest({
    url: 'https://api.example.com/prefetch',
    method: 'GET',
    priority: NetworkManager.PRIORITY_LOW
});
```

#### Practical Example

```javascript
const NetworkManager = require('ti.network.manager');

// High priority: User's current action
const submitOrder = NetworkManager.createRequest({
    url: 'https://api.example.com/orders',
    method: 'POST',
    body: JSON.stringify(orderData),
    priority: NetworkManager.PRIORITY_HIGH
});

submitOrder.addEventListener('complete', (e) => {
    if (e.success) {
        showOrderConfirmation();
    }
});

submitOrder.send();

// Low priority: Prefetch next page data
const prefetchNextPage = NetworkManager.createRequest({
    url: 'https://api.example.com/products?page=2',
    method: 'GET',
    priority: NetworkManager.PRIORITY_LOW
});

prefetchNextPage.send();
```

#### Dynamic Priority

```javascript
const NetworkManager = require('ti.network.manager');

function fetchUserData(isUrgent) {
    const request = NetworkManager.createRequest({
        url: 'https://api.example.com/user/profile',
        method: 'GET',
        priority: isUrgent 
            ? NetworkManager.PRIORITY_HIGH 
            : NetworkManager.PRIORITY_NORMAL
    });
    
    request.send();
}

// User clicked profile button - high priority
fetchUserData(true);

// Background refresh - normal priority
setInterval(() => {
    fetchUserData(false);
}, 300000); // Every 5 minutes
```

#### Use Cases

1. **Payment Processing** - Prioritize checkout and payment requests over other operations.
2. **Search Results** - Give high priority to search queries for immediate user feedback.
3. **Image Loading** - Load visible images with high priority, prefetch others with low priority.
4. **Chat Messages** - Prioritize sending and receiving messages over loading history.
5. **Analytics** - Send analytics data with low priority to not affect user experience.

---

### Feature 8: Multipart Upload Progress

**Upload multiple files with per-file progress tracking.** Perfect for photo galleries and document uploads.

#### Upload Multiple Images

```javascript
const NetworkManager = require('ti.network.manager');

const image1 = Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'photo1.jpg');
const image2 = Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'photo2.jpg');
const image3 = Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'photo3.jpg');

const upload = NetworkManager.createMultipartUpload({
    url: 'https://api.example.com/upload/images',
    headers: {
        'Authorization': 'Bearer ' + getAuthToken()
    },
    priority: NetworkManager.PRIORITY_HIGH,
    fields: [
        // Text fields
        {
            type: 'text',
            name: 'userId',
            value: getCurrentUserId()
        },
        {
            type: 'text',
            name: 'albumId',
            value: '12345'
        },
        
        // File fields
        {
            type: 'file',
            name: 'image1',
            filename: 'photo1.jpg',
            mimeType: 'image/jpeg',
            data: Ti.Utils.base64encode(image1.read()).text
        },
        {
            type: 'file',
            name: 'image2',
            filename: 'photo2.jpg',
            mimeType: 'image/jpeg',
            data: Ti.Utils.base64encode(image2.read()).text
        },
        {
            type: 'file',
            name: 'image3',
            filename: 'photo3.jpg',
            mimeType: 'image/jpeg',
            data: Ti.Utils.base64encode(image3.read()).text
        }
    ]
});

// Overall upload progress
upload.addEventListener('progress', (e) => {
    const percent = (e.progress * 100).toFixed(1);
    console.log('Overall progress: ' + percent + '%');
    overallProgressBar.value = percent;
    
    if (e.currentFile) {
        statusLabel.text = 'Uploading ' + e.currentFile;
    }
});

// Individual file progress
upload.addEventListener('fileprogress', (e) => {
    const percent = (e.progress * 100).toFixed(1);
    console.log('[' + e.filename + '] ' + percent + '%');
    updateFileStatus(e.filename, percent);
});

upload.addEventListener('complete', (e) => {
    if (e.success) {
        console.log('All files uploaded successfully!');
        showSuccessMessage('Upload complete!');
    }
});

upload.upload();
```

#### Upload Video with Thumbnail

```javascript
const NetworkManager = require('ti.network.manager');

const videoFile = Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'video.mp4');
const thumbFile = Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'thumb.jpg');

const upload = NetworkManager.createMultipartUpload({
    url: 'https://api.example.com/videos/upload',
    headers: {
        'Authorization': 'Bearer ' + getAuthToken()
    },
    fields: [
        {
            type: 'text',
            name: 'title',
            value: 'My Amazing Video'
        },
        {
            type: 'text',
            name: 'description',
            value: 'A great video about...'
        },
        {
            type: 'file',
            name: 'video',
            filename: 'video.mp4',
            mimeType: 'video/mp4',
            data: Ti.Utils.base64encode(videoFile.read()).text
        },
        {
            type: 'file',
            name: 'thumbnail',
            filename: 'thumb.jpg',
            mimeType: 'image/jpeg',
            data: Ti.Utils.base64encode(thumbFile.read()).text
        }
    ]
});

upload.addEventListener('fileprogress', (e) => {
    if (e.filename === 'video.mp4') {
        videoProgress.value = e.progress * 100;
    } else if (e.filename === 'thumb.jpg') {
        thumbProgress.value = e.progress * 100;
    }
});

upload.upload();
```

#### Upload Documents with Metadata

```javascript
const NetworkManager = require('ti.network.manager');

const doc1 = Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'report.pdf');
const doc2 = Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'data.xlsx');

const upload = NetworkManager.createMultipartUpload({
    url: 'https://api.example.com/documents/upload',
    fields: [
        {
            type: 'text',
            name: 'projectId',
            value: 'PROJECT-123'
        },
        {
            type: 'text',
            name: 'uploadDate',
            value: new Date().toISOString()
        },
        {
            type: 'file',
            name: 'document1',
            filename: 'report.pdf',
            mimeType: 'application/pdf',
            data: Ti.Utils.base64encode(doc1.read()).text
        },
        {
            type: 'file',
            name: 'document2',
            filename: 'data.xlsx',
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            data: Ti.Utils.base64encode(doc2.read()).text
        }
    ]
});

upload.upload();
```

#### Upload Profile Picture

```javascript
const NetworkManager = require('ti.network.manager');

function uploadProfilePicture(imageBlob) {
    const upload = NetworkManager.createMultipartUpload({
        url: 'https://api.example.com/user/profile/picture',
        headers: {
            'Authorization': 'Bearer ' + getAuthToken()
        },
        fields: [
            {
                type: 'text',
                name: 'userId',
                value: getCurrentUserId()
            },
            {
                type: 'file',
                name: 'avatar',
                filename: 'avatar.jpg',
                mimeType: 'image/jpeg',
                data: Ti.Utils.base64encode(imageBlob).text
            }
        ]
    });
    
    upload.addEventListener('progress', (e) => {
        avatarProgress.value = e.progress * 100;
    });
    
    upload.addEventListener('complete', (e) => {
        if (e.success) {
            const response = JSON.parse(e.body);
            userAvatar.image = response.avatarUrl;
            showSuccessMessage('Profile picture updated!');
        }
    });
    
    upload.upload();
}
```

#### Use Cases

1. **Photo Gallery Uploads** - Upload multiple photos with individual progress tracking for each image.
2. **Video Sharing** - Upload video files with thumbnails and metadata in a single request.
3. **Document Management** - Upload multiple documents with descriptions and tags.
4. **Profile Updates** - Update user profiles with avatar images and additional data.
5. **Form Submissions** - Submit forms with file attachments and structured data.

---

### Feature 9: HTTP/2 & HTTP/3 Support

**Automatic support for modern HTTP protocols.** Provides better performance through multiplexing and header compression.

- ⚠️ **HTTP/3**: Available on iOS 15+, not available on Android (OkHttp 4.x limitation)

HTTP/2 and HTTP/3 support is automatic and requires no special configuration. The module uses `URLSession` which automatically negotiates the best protocol with the server.

#### Automatic Protocol Negotiation

```javascript
const NetworkManager = require('ti.network.manager');

// This request will automatically use HTTP/2 or HTTP/3 if the server supports it
const request = NetworkManager.createRequest({
    url: 'https://api.example.com/data',
    method: 'GET'
});

request.addEventListener('complete', (e) => {
    console.log('Request completed');
    // HTTP/2 or HTTP/3 was used automatically if available
});

request.send();
```

#### Benefits Demonstration

```javascript
const NetworkManager = require('ti.network.manager');

// Make multiple parallel requests - HTTP/2 multiplexing makes this efficient
const requests = [
    'https://api.example.com/users',
    'https://api.example.com/products',
    'https://api.example.com/orders',
    'https://api.example.com/analytics'
];

requests.forEach(url => {
    const request = NetworkManager.createRequest({
        url: url,
        method: 'GET'
    });
    
    request.addEventListener('complete', (e) => {
        console.log('Loaded:', url);
        // With HTTP/2, all requests share the same connection
        // Much faster than HTTP/1.1's connection per request
    });
    
    request.send();
});
```

#### Use Cases

1. **Parallel Data Loading** - Load multiple resources simultaneously with efficient connection reuse.
2. **Real-time Applications** - Reduced latency for time-sensitive operations.
3. **Mobile Performance** - Better battery life and network efficiency.
4. **Large API Responses** - Improved performance for data-heavy applications.
5. **Future-Proofing** - Automatically benefit from protocol improvements.

---

### Feature 10: WebSocket Support

**Real-time bidirectional communication.** Perfect for chat applications, live updates, and collaborative features.

#### Basic WebSocket Connection

```javascript
const NetworkManager = require('ti.network.manager');

const ws = NetworkManager.createWebSocket({
    url: 'wss://api.example.com/realtime',
    headers: {
        'Authorization': 'Bearer ' + getAuthToken()
    }
});

ws.addEventListener('open', () => {
    console.log('WebSocket connected!');
    
    // Send a message
    ws.send(JSON.stringify({
        action: 'subscribe',
        channel: 'notifications'
    }));
});

ws.addEventListener('message', (e) => {
    console.log('Message received:', e.data);
    const data = JSON.parse(e.data);
    handleNotification(data);
});

ws.addEventListener('close', (e) => {
    console.log('WebSocket closed');
    console.log('Code:', e.code);
    console.log('Reason:', e.reason);
});

ws.addEventListener('error', (e) => {
    console.error('WebSocket error:', e.error);
});

ws.connect();
```

#### Chat Application

```javascript
const NetworkManager = require('ti.network.manager');

const chatWS = NetworkManager.createWebSocket({
    url: 'wss://api.example.com/chat',
    headers: {
        'Authorization': 'Bearer ' + getAuthToken()
    }
});

chatWS.addEventListener('open', () => {
    console.log('Connected to chat server');
    statusLabel.text = 'Online';
    statusLabel.color = 'green';
    
    // Join chat room
    chatWS.send(JSON.stringify({
        type: 'join',
        roomId: currentRoomId,
        userId: getCurrentUserId()
    }));
});

chatWS.addEventListener('message', (e) => {
    const message = JSON.parse(e.data);
    
    switch (message.type) {
        case 'message':
            displayMessage(message.user, message.text, message.timestamp);
            break;
        case 'user_joined':
            showNotification(message.user + ' joined the chat');
            break;
        case 'user_left':
            showNotification(message.user + ' left the chat');
            break;
        case 'typing':
            showTypingIndicator(message.user);
            break;
    }
});

// Send message
sendButton.addEventListener('click', () => {
    const text = messageInput.value;
    
    chatWS.send(JSON.stringify({
        type: 'message',
        text: text,
        timestamp: new Date().toISOString()
    }));
    
    messageInput.value = '';
});

// Send typing indicator
messageInput.addEventListener('change', () => {
    chatWS.send(JSON.stringify({
        type: 'typing',
        userId: getCurrentUserId()
    }));
});

chatWS.connect();
```

#### Keep-Alive with Ping/Pong

```javascript
const NetworkManager = require('ti.network.manager');

const ws = NetworkManager.createWebSocket({
    url: 'wss://api.example.com/live'
});

ws.addEventListener('open', () => {
    console.log('WebSocket connected');
    
    // Send ping every 30 seconds to keep connection alive
    setInterval(() => {
        ws.ping();
    }, 30000);
});

ws.addEventListener('pong', () => {
    console.log('Pong received - connection alive');
});

ws.connect();
```

#### Binary Data Transfer

```javascript
const NetworkManager = require('ti.network.manager');

const ws = NetworkManager.createWebSocket({
    url: 'wss://api.example.com/binary'
});

ws.addEventListener('open', () => {
    // Send binary data (base64 encoded)
    const imageFile = Ti.Filesystem.getFile(Ti.Filesystem.applicationDataDirectory, 'image.jpg');
    const base64Data = Ti.Utils.base64encode(imageFile.read()).text;
    
    ws.sendBinary(base64Data);
});

ws.addEventListener('binary', (e) => {
    // Receive binary data (base64 encoded)
    console.log('Binary data received');
    const data = Ti.Utils.base64decode(e.data);
    // Process binary data
});

ws.connect();
```

#### Reconnection Logic

```javascript
const NetworkManager = require('ti.network.manager');

let reconnectAttempts = 0;
const maxReconnectAttempts = 5;

function connectWebSocket() {
    const ws = NetworkManager.createWebSocket({
        url: 'wss://api.example.com/live'
    });
    
    ws.addEventListener('open', () => {
        console.log('WebSocket connected');
        reconnectAttempts = 0;
        statusIndicator.backgroundColor = 'green';
    });
    
    ws.addEventListener('close', (e) => {
        console.log('WebSocket closed');
        statusIndicator.backgroundColor = 'red';
        
        // Attempt to reconnect
        if (reconnectAttempts < maxReconnectAttempts) {
            reconnectAttempts++;
            const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), 30000);
            
            console.log('Reconnecting in ' + (delay / 1000) + ' seconds...');
            
            setTimeout(() => {
                connectWebSocket();
            }, delay);
        } else {
            console.log('Max reconnection attempts reached');
            showErrorMessage('Unable to connect. Please check your connection.');
        }
    });
    
    ws.addEventListener('error', (e) => {
        console.error('WebSocket error:', e.error);
    });
    
    ws.connect();
    
    return ws;
}

const websocket = connectWebSocket();
```

#### Use Cases

1. **Chat Applications** - Real-time messaging with instant delivery and typing indicators.
2. **Live Notifications** - Push notifications for order updates, social interactions, or system alerts.
3. **Collaborative Editing** - Real-time document collaboration with multiple users.
4. **Live Sports Scores** - Instant updates for sports events and games.
5. **Stock Trading** - Real-time stock prices and trading information.

---

## API Reference

### Module Methods

#### `createRequest(config)`

Create a standard HTTP request.

**Parameters:**
- `url` (String) - The request URL
- `method` (String) - HTTP method (GET, POST, PUT, DELETE, etc.)
- `headers` (Object) - Request headers
- `body` (String) - Request body
- `priority` (String) - Priority level (PRIORITY_HIGH, PRIORITY_NORMAL, PRIORITY_LOW)
- `cache` (Object) - Cache configuration
  - `policy` (String) - Cache policy
  - `ttl` (Number) - Time to live in seconds
- `retry` (Object) - Retry configuration
  - `max` (Number) - Maximum retry attempts
  - `backoff` (String) - Backoff strategy
  - `baseDelay` (Number) - Base delay in seconds
  - `retryOn` (Array) - HTTP status codes to retry on

**Returns:** `TNMRequestProxy`

**Events:**
- `progress` - Upload/download progress
- `complete` - Request completed
- `error` - Request failed
- `cancelled` - Request cancelled

---

#### `createStreamRequest(config)`

Create a streaming HTTP request for SSE.

**Parameters:**
- `url` (String) - The request URL
- `method` (String) - HTTP method
- `headers` (Object) - Request headers
- `body` (String) - Request body
- `priority` (String) - Priority level

**Returns:** `TiHTTPStreamProxy`

**Events:**
- `chunk` - Data chunk received
- `complete` - Stream completed
- `error` - Stream error
- `cancelled` - Stream cancelled

---

#### `createWebSocket(config)`

Create a WebSocket connection.

**Parameters:**
- `url` (String) - WebSocket URL (wss:// or ws://)
- `headers` (Object) - Connection headers

**Returns:** `TNMWebSocketProxy`

**Events:**
- `open` - Connection opened
- `message` - Text message received
- `binary` - Binary message received
- `pong` - Pong response received
- `close` - Connection closed
- `error` - Connection error

---

#### `createBackgroundTransfer(config)`

Create a background transfer (download or upload).

**Parameters:**
- `type` (String) - Transfer type ('download' or 'upload')
- `url` (String) - The request URL
- `destination` (String) - Download destination path (for downloads)
- `file` (String) - Upload file path (for uploads)
- `headers` (Object) - Request headers

**Returns:** `TNMBackgroundTransferProxy`

**Events:**
- `progress` - Transfer progress
- `complete` - Transfer completed
- `error` - Transfer error
- `paused` - Transfer paused
- `resumed` - Transfer resumed
- `cancelled` - Transfer cancelled

---

#### `createMultipartUpload(config)`

Create a multipart upload request.

**Parameters:**
- `url` (String) - The request URL
- `headers` (Object) - Request headers
- `priority` (String) - Priority level
- `fields` (Array) - Array of field objects
  - Text field: `{ type: 'text', name: String, value: String }`
  - File field: `{ type: 'file', name: String, filename: String, mimeType: String, data: String }`

**Returns:** `TNMMultipartUploadProxy`

**Events:**
- `progress` - Overall upload progress
- `fileprogress` - Individual file progress
- `complete` - Upload completed
- `error` - Upload error
- `cancelled` - Upload cancelled

---

#### `setCertificatePinning(domain, hashes)`

Configure certificate pinning for a domain.

**Parameters:**
- `domain` (String) - Domain to pin
- `hashes` (Array) - Array of SHA-256 certificate hashes

---

#### `addRequestInterceptor(callback)`

Add a global request interceptor.

**Parameters:**
- `callback` (Function) - Interceptor function that receives and returns config object

---

#### `addResponseInterceptor(callback)`

Add a global response interceptor.

**Parameters:**
- `callback` (Function) - Interceptor function that receives and returns response object

---

#### `clearCache(domain)`

Clear cached responses.

**Parameters:**
- `domain` (String, optional) - Clear cache for specific domain, or all cache if omitted

---

### Constants

#### Priority Levels
- `PRIORITY_HIGH` - High priority (0.75)
- `PRIORITY_NORMAL` - Normal priority (0.5)
- `PRIORITY_LOW` - Low priority (0.25)

#### Cache Policies
- `CACHE_POLICY_NETWORK_ONLY` - Never use cache
- `CACHE_POLICY_CACHE_FIRST` - Use cache if available, otherwise network
- `CACHE_POLICY_NETWORK_FIRST` - Try network first, fallback to cache

#### Retry Backoff Strategies
- `RETRY_BACKOFF_LINEAR` - Linear backoff (1x, 2x, 3x, 4x...)
- `RETRY_BACKOFF_EXPONENTIAL` - Exponential backoff (1x, 2x, 4x, 8x...)

---

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request