require 'bundler/setup'
require 'vcr'
require 'puppeteer'
require 'uri'
require 'webmock'
require 'fileutils'
require 'digest'
require 'base64'
require 'json'
require 'net/http'
require 'logger'

# Initialize logger
LOGGER = Logger.new('vcr.log')
LOGGER.level = Logger::DEBUG

TIMEOUT_PAGE_LOAD = 30000
TIMEOUT_SELECTOR_BODY = 5000
TIMEOUT_SELECTOR_MAIN = 10000
PUPPETEER_ARGS = [
  '--no-sandbox',
  '--disable-setuid-sandbox',
  '--disable-dev-shm-usage',
  '--disable-accelerated-2d-canvas',
  '--disable-gpu',
  '--disable-features=site-per-process',
  '--disable-blink-features=AutomationControlled',
  '--enable-mobile-emulation',
  '--enable-touch-events',
  '--enable-viewport'
]

class ProductPageRecorder
  def initialize
    configure_vcr
    @recorded_interactions = []
  end

  def record_page(url)
    puts "Recording page: #{url}"
    LOGGER.info("Recording page: #{url}")
    
    # Create a filesystem-friendly cassette name
    uri = URI(url)
    host_dir = uri.host.gsub('.', '_')
    cassette_name = "#{host_dir}/#{Digest::SHA256.hexdigest(url)}"
    puts "Cassette: #{cassette_name}"
    LOGGER.info("Cassette: #{cassette_name}")
    
    # Ensure directory exists
    FileUtils.mkdir_p(File.join('vcr_cassettes', host_dir))
    
    # Record all requests in a single cassette
    VCR.turned_off do
      WebMock.allow_net_connect!
      browser = nil
      begin
        # Launch browser with mobile configuration
        browser = Puppeteer.launch(
          headless: false,
          args: PUPPETEER_ARGS
        )
        
        context = browser.create_incognito_browser_context
        page = context.new_page
        
        # Configure mobile viewport
        page.viewport = Puppeteer::Viewport.new(
          width: 390,
          height: 844,
          device_scale_factor: 3,
          is_mobile: true,
          has_touch: true
        )
        
        # Set mobile user agent
        page.set_user_agent('Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1')
        
        # Track pending requests
        pending_requests = {}
        
        # Listen to all network requests
        page.on('request') do |request|
          puts "Request: #{request.url}"
          LOGGER.debug("Request: #{request.url}")
          pending_requests["#{request.url}-#{Time.now.to_f}"] = {
            method: request.method,
            headers: request.headers,
            body: request.post_data
          }
        end
        
        page.on('response') do |response|
          url = response.url
          puts "Response: #{url} (#{response.status})"
          LOGGER.debug("Response: #{url} (#{response.status})")
          
          # Get response body as text, fallback to buffer for binary data
          response.text.then do |body|
            body ||= response.buffer.then { |buf| Base64.strict_encode64(buf) } rescue ''
            
            request_data = pending_requests.delete(url) || {}
            headers = response.headers
            
            interaction = {
              request: {
                method: request_data[:method] || 'GET',
                uri: url,
                body: {
                  encoding: 'UTF-8',
                  string: request_data[:body].to_s
                },
                headers: request_data[:headers] || {}
              },
              response: {
                status: {
                  code: response.status,
                  message: response.status_text
                },
                headers: headers,
                body: {
                  encoding: 'UTF-8',
                  string: body
                }
              },
              recorded_at: Time.now.utc
            }
            
            @recorded_interactions << interaction
          rescue => e
            puts "Error recording response for URL #{url}: #{e.message}"
            LOGGER.error("Error recording response for URL #{url}: #{e.message}")
          end
        end
        
        # Set default timeout
        page.default_timeout = TIMEOUT_PAGE_LOAD
        
        # Wait for page load with navigation options
        puts "Loading page..."
        LOGGER.info("Loading page...")
        response = page.goto(url, 
          wait_until: 'networkidle0',
          timeout: TIMEOUT_PAGE_LOAD
        )
        puts "Page loaded with status: #{response.status}"
        LOGGER.info("Page loaded with status: #{response.status}")
        
        # Wait for network to settle by waiting for key elements
        puts "Waiting for page content to load..."
        LOGGER.info("Waiting for page content to load...")
        begin
          # Wait for body element to ensure basic page structure is loaded
          page.wait_for_selector('body', timeout: TIMEOUT_SELECTOR_BODY)
          
          # Wait for a common element that indicates the main content is loaded
          page.wait_for_selector('main, #main, .main, [role="main"], .product-title, .product-details', timeout: TIMEOUT_SELECTOR_MAIN)
          
          # Give extra time for dynamic content and pending requests to complete
          sleep 5
        rescue => e
          puts "Warning: Timeout waiting for page content: #{e.message}"
          LOGGER.warn("Timeout waiting for page content: #{e.message}")
        end
      ensure
        if browser
          puts "Closing browser..."
          LOGGER.info("Closing browser...")
          context&.close
          browser.close
        end
      end
      
      # Save recorded interactions to cassette
      cassette_path = File.join('vcr_cassettes', "#{cassette_name}.yml")
      File.write(cassette_path, {
        'http_interactions' => @recorded_interactions,
        'recorded_with' => 'VCR 6.1.0'
      }.to_yaml)
    end
    
    puts "Finished recording to cassette: #{cassette_name}"
    LOGGER.info("Finished recording to cassette: #{cassette_name}")
  end

  private

  def configure_vcr
    VCR.configure do |config|
      config.cassette_library_dir = "vcr_cassettes"
      config.hook_into :webmock
      config.allow_http_connections_when_no_cassette = true
      config.debug_logger = File.open('vcr.log', 'w')
    end
  end
end

if ARGV.length != 1
  puts "vcr-puppet: Record web pages and their resources for reliable playback"
  puts "\nUsage: #{$0} <url>"
  puts "\nExample:"
  puts "  bundle exec ruby #{$0} https://example.com/product"
  puts "\nRecordings are stored in the vcr_cassettes directory, organized by domain."
  exit 1
end

recorder = ProductPageRecorder.new
recorder.record_page(ARGV[0]) 