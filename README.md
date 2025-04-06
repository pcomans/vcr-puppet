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

1. **Set up Ruby Version:** This project requires Ruby `3.4.2`. We recommend using `rbenv` to manage Ruby versions.

    ```bash
    # Install rbenv (if you don't have it)
    brew install rbenv

    # Install the required Ruby version (if not already installed)
    rbenv install $(cat .ruby-version)

    # Set the local Ruby version for this project (reads from .ruby-version)
    rbenv local $(cat .ruby-version)

    # Verify the correct Ruby version is active
    ruby -v
    ```

2. **Install Dependencies:** Use Bundler to install the required gems.

    ```bash
    # Install bundler if you haven't already (needed for the first time)
    gem install bundler

    # Install project gems
    bundle install
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