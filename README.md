# vcr-puppet

A Ruby tool that combines VCR and Puppeteer to record web pages and their resources for reliable playback in tests.

![VCR-Puppet Demo](assets/image.png)

## Features

- Records full page content including dynamically loaded resources
- Handles both text and binary content appropriately
- Stores text content (HTML, JSON, etc.) in readable format
- Base64 encodes binary content (images, PDFs, etc.)
- Uses Puppeteer for JavaScript-rendered content
- Waits for dynamic content to load

## Prerequisites

- Ruby 2.6 or higher
- Bundler
- Chrome/Chromium (for Puppeteer)

## Installation

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd vcr-puppet
   ```

2. Install dependencies:
   ```bash
   bundle install --path vendor/bundle
   ```

## Usage

Run the script with a URL to record:

```bash
bundle exec ruby record_product.rb "https://example.com/product"
```

The script will:
1. Launch a Chrome instance
2. Load the specified URL
3. Wait for the page and its resources to load
4. Record all network requests and responses
5. Save the recording as a VCR cassette

Recordings are stored in the `vcr_cassettes` directory, organized by domain.

## Output Format

Recordings are stored as YAML files with:
- Request details (method, URL, headers)
- Response details (status, headers)
- Response body (readable text or base64 encoded binary)
- Content type information
- Encoding metadata

## Common Issues

- If you see "Chrome not found" errors, ensure Chrome/Chromium is installed
- For "Permission denied" errors, check file permissions in the vcr_cassettes directory
- If pages aren't fully loading, try adjusting the timeout values in the script

## Contributing

1. Fork the repository
2. Create your feature branch
3. Make your changes
4. Submit a pull request

## License

MIT License - feel free to use and modify as needed. 