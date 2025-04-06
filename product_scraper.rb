require 'puppeteer'
require 'nokogiri'
require 'uri' # For URL parsing if needed

class ProductScraper
  # Add Puppeteer launch args if needed
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
  TIMEOUT_PAGE_LOAD = 30000 # Example timeout
  TIMEOUT_SELECTOR_BODY = 5000
  TIMEOUT_SELECTOR_MAIN = 10000

  def initialize(url)
    @url = url
    validate_url # Good practice
  end

  def scrape
    html_content = fetch_rendered_html
    parse_html(html_content)
  end

  private

  def validate_url
    raise ArgumentError, "Invalid URL: #{@url}" unless @url && URI.parse(@url).is_a?(URI::HTTP)
  rescue URI::InvalidURIError
    raise ArgumentError, "Invalid URL: #{@url}"
  end

  def fetch_rendered_html
    browser = nil
    html = nil
    begin
      browser = Puppeteer.launch(headless: false, args: PUPPETEER_ARGS)
      context = browser.create_incognito_browser_context # Use incognito context
      page = context.new_page

      # Set default timeout like in vcr-puppet.rb
      page.default_timeout = TIMEOUT_PAGE_LOAD

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

      # Navigate and wait for rendering
      page.goto(@url, wait_until: 'networkidle0', timeout: TIMEOUT_PAGE_LOAD)

      # Add explicit waits like in vcr-puppet.rb
      begin
        # Wait for body element
        page.wait_for_selector('body', timeout: TIMEOUT_SELECTOR_BODY)
        # Wait for main content element
        page.wait_for_selector('main, #main, .main, [role="main"], .product-title, .product-details', timeout: TIMEOUT_SELECTOR_MAIN)
        # Give extra time for dynamic content
        sleep 5
      rescue Puppeteer::TimeoutError => e
        # Log warning or handle timeout for waits if necessary, but don't necessarily fail
        puts "Warning: Timeout waiting for specific page elements after navigation: #{e.message}"
      end

      # Get the final rendered HTML
      html = page.content
    ensure
      # Close context then browser
      context&.close
      browser&.close
    end
    html
  end

  def parse_html(html_content)
    doc = Nokogiri::HTML(html_content)

    # --- Placeholder Selectors ---
    # These need to be replaced with the ACTUAL CSS selectors for Amazon
    price = doc.at_css('.price-selector')&.text&.strip
    brand = doc.at_css('.brand-selector')&.text&.strip
    # Dimensions/ASIN often in a details table/list
    dimensions = doc.at_xpath("//th[contains(text(), 'Product Dimensions')]/following-sibling::td")&.text&.strip
    asin = doc.at_xpath("//th[contains(text(), 'ASIN')]/following-sibling::td")&.text&.strip
    # --- End Placeholder Selectors ---

    {
      price: price,
      brand: brand,
      product_dimensions: dimensions,
      asin: asin
    }
  end
end