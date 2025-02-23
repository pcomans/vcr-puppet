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

class ProductPageRecorder
  def initialize
    configure_vcr
  end

  def record_page(url)
    puts "Recording page: #{url}"
    
    # Create a filesystem-friendly cassette name
    uri = URI(url)
    host_dir = uri.host.gsub('.', '_')
    cassette_name = "#{host_dir}/#{Digest::SHA256.hexdigest(url)}"
    puts "Cassette: #{cassette_name}"
    
    # Ensure directory exists
    FileUtils.mkdir_p(File.join('vcr_cassettes', host_dir))
    
    # Record the main page request first
    VCR.use_cassette(cassette_name, record: :new_episodes) do
      begin
        # Make a direct request to get the main page
        response = Net::HTTP.get_response(uri)
        puts "Recorded main page response: #{response.code}"
      rescue => e
        puts "Warning: Failed to record main page: #{e.message}"
      end
      
      browser = nil
      begin
        # Launch browser with more stable configuration
        browser = Puppeteer.launch(
          headless: false,
          args: [
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--window-size=1280,800',
            '--disable-dev-shm-usage',
            '--disable-accelerated-2d-canvas',
            '--disable-gpu',
            '--disable-features=site-per-process'
          ]
        )
        
        context = browser.create_incognito_browser_context
        page = context.new_page
        
        # Set a realistic user agent
        page.set_user_agent('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36')
        
        # Set default timeout
        page.default_timeout = 30000
        
        # Wait for page load
        puts "Loading page..."
        response = page.goto(url)
        puts "Page loaded with status: #{response.status}"
        
        # Wait for network to settle by waiting for key elements
        puts "Waiting for page content to load..."
        begin
          # Wait for body element to ensure basic page structure is loaded
          page.wait_for_selector('body', timeout: 5000)
          
          # Wait for a common element that indicates the main content is loaded
          # This could be the main content div, product title, etc.
          page.wait_for_selector('main, #main, .main, [role="main"]', timeout: 10000)
        rescue => e
          puts "Warning: Timeout waiting for page content: #{e.message}"
        end
        
        # Give a moment for any dynamic content
        puts "Waiting for dynamic content..."
        sleep 3
        
        puts "Recording network activity..."
        sleep 2
      ensure
        if browser
          puts "Closing browser..."
          context&.close
          browser.close
        end
      end
    end
    
    puts "Finished recording to cassette: #{cassette_name}"
  end

  private

  def configure_vcr
    VCR.configure do |config|
      config.cassette_library_dir = "vcr_cassettes"
      config.hook_into :webmock
      config.allow_http_connections_when_no_cassette = true
      
      # Handle binary responses
      config.before_record do |interaction|
        content_type = interaction.response.headers['content-type']&.first&.downcase
        
        if interaction.response.body.encoding == Encoding::ASCII_8BIT
          # Try to handle common formats based on content type
          case content_type
          when /^text/, /json/, /javascript/, /xml/, /html/, /application\/json/
            # For text-based formats, try to decode as UTF-8
            begin
              interaction.response.body.force_encoding('UTF-8')
              unless interaction.response.body.valid_encoding?
                interaction.response.body = interaction.response.body.encode('UTF-8', 'UTF-8', invalid: :replace, undef: :replace)
              end
            rescue => e
              puts "Warning: Failed to decode as UTF-8: #{e.message}"
              interaction.response.body = Base64.strict_encode64(interaction.response.body)
              interaction.response.headers['x-encoding'] = ['base64']
            end
          when /^image/, /^audio/, /^video/, /^application\/pdf/, /^application\/zip/, /octet-stream/
            # For binary content, store content type and use base64
            interaction.response.body = Base64.strict_encode64(interaction.response.body)
            interaction.response.headers['x-encoding'] = ['base64']
            interaction.response.headers['x-original-content-type'] = [content_type]
          else
            # For unknown types, try UTF-8 first
            begin
              interaction.response.body.force_encoding('UTF-8')
              if !interaction.response.body.valid_encoding?
                interaction.response.body = Base64.strict_encode64(interaction.response.body)
                interaction.response.headers['x-encoding'] = ['base64']
                puts "Warning: Unknown content type #{content_type} - using base64"
              end
            rescue => e
              interaction.response.body = Base64.strict_encode64(interaction.response.body)
              interaction.response.headers['x-encoding'] = ['base64']
              puts "Warning: Failed to handle content type #{content_type}: #{e.message}"
            end
          end
        end
      end
      
      # Debug logging
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