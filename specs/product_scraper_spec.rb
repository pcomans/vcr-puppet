require 'rspec'
require 'vcr'
require 'webmock/rspec' # Optional, but good practice with VCR and RSpec

# Configure VCR
VCR.configure do |config|
  config.cassette_library_dir = "vcr_cassettes"
  config.hook_into :webmock
  # Allow connections if no cassette is available (useful for initial recording)
  config.allow_http_connections_when_no_cassette = false
  # Filter sensitive data if needed
  # config.filter_sensitive_data('<FILTERED>') { 'your_secret_data' }
end

describe ProductScraper do
  let(:url) { "https://www.amazon.com/some-product-url" } # Replace with the actual URL if needed
  let(:scraper) { ProductScraper.new(url) }
  let(:cassette_name) { "www_amazon_com/9e6a5691c2a350aac47d6d56d431105908c54b4548ae5746b8d87da556026b18" }

  it 'extracts product details from the recorded page' do
    VCR.use_cassette(cassette_name) do
      # In a real test, you might make an HTTP request here if the scraper needs it
      # For now, we assume the scraper can work with the cassette data implicitly
      # or that the scrape method itself uses the loaded VCR data.

      # Call the method under test
      product_data = scraper.scrape

      # Assertions for the expected data
      expect(product_data).to include(
        price: '$19.99',
        brand: 'ExampleBrand',
        product_dimensions: '10 x 5 x 2 inches',
        asin: 'B0EXAMPLE123'
      )
      expect(product_data[:price]).not_to be_nil
      expect(product_data[:brand]).not_to be_nil
      expect(product_data[:product_dimensions]).not_to be_nil
      expect(product_data[:asin]).not_to be_nil
    end
  end
end 