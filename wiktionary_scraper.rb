require 'nokogiri'
require 'uri'
require 'net/http' # Added for HTTP requests
require 'yaml'       # For YAML serialization
require 'fileutils'  # For directory creation

class WiktionaryScraper # Renamed from ProductScraper
  VCR_DIR = 'vcr_cassettes'.freeze

  # Removed PUPPETEER_ARGS and TIMEOUT_PAGE_LOAD

  def initialize(url)
    @url = url
    @word = URI.parse(url).path.split('/').last # Extract word from URL
    validate_url # Good practice
  end

  def scrape
    html_content = fetch_html # Renamed from fetch_rendered_html
    # We need the raw html_content for the VCR body
    scraped_data = parse_html(html_content)
    save_vcr(html_content) # Pass the raw HTML
    scraped_data # Return the parsed data
  end

  private

  def validate_url
    uri = URI.parse(@url)
    raise ArgumentError, "Invalid URL: #{@url}" unless @url && uri.is_a?(URI::HTTP) && uri.host&.include?('wiktionary.org')
  rescue URI::InvalidURIError
    raise ArgumentError, "Invalid URL: #{@url}"
  end

  def fetch_html # Replaced Puppeteer logic
    uri = URI.parse(@url)
    response = Net::HTTP.get_response(uri)
    raise "Failed to fetch URL: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)
    response.body
  end

  def parse_html(html_content)
    doc = Nokogiri::HTML(html_content)

    # Find the English language section first
    english_section = doc.at_xpath("//h2[span[@id='English']]")
    unless english_section
      puts "English section not found."
      return {}
    end

    # Search within the English section for relevant subsections
    current_node = english_section.next_element
    etymology = nil
    pronunciation_details = {}
    definitions = []
    synonyms = nil

    while current_node && current_node.name != 'h2' # Stop at the next language section
      if current_node.name == 'h3' && current_node.at_css('#Etymology')
        # Etymology is typically the paragraph(s) following the H3
        etymology_p = current_node.xpath("./following-sibling::p[1]")
        etymology = etymology_p.text.strip if etymology_p
      elsif current_node.name == 'h3' && current_node.at_css('#Pronunciation')
        # Pronunciation details often follow in a UL
        pronunciation_ul = current_node.xpath("./following-sibling::ul[1]")
        if pronunciation_ul
          ipa_node = pronunciation_ul.at_css("span.IPA")
          pronunciation_details[:ipa] = ipa_node.text.strip if ipa_node
          audio_node = pronunciation_ul.at_css("source[type='audio/ogg']")
          # Construct full URL if source is relative
          if audio_node && audio_node['src']
             audio_src = audio_node['src']
             audio_url = audio_src.start_with?('//') ? "https:" + audio_src : audio_src
             pronunciation_details[:audio_url] = audio_url
          end
        end
      elsif current_node.name == 'h3' && current_node.at_css('#Noun') # Assuming we want Noun definitions
        # Definitions are usually in an OL following the H3 (part of speech)
        definitions_ol = current_node.xpath("./following-sibling::ol[1]")
        if definitions_ol
          definitions_ol.css('li').each do |li|
            # Remove examples (often in 'dl' or starting with '*')
            li.css('dl, ul.usage-examples').remove
            definitions << li.text.strip unless li.text.strip.empty?
          end
        end

        # Look for Synonyms section immediately after the noun block elements
        synonyms_h4 = current_node.xpath("./following-sibling::h4[span[@id='Synonyms']]").first
        if synonyms_h4
          synonyms_ul = synonyms_h4.xpath("./following-sibling::ul[1]")
          if synonyms_ul
            synonyms = synonyms_ul.css('li > a').map { |a| a.text.strip }
          end
        end
      end
      current_node = current_node.next_element
    end

    {
      etymology: etymology,
      pronunciation: pronunciation_details,
      definitions: definitions,
      synonyms: synonyms || [] # Ensure synonyms is always an array
    }
  end

  def save_vcr(html_response_body)
    FileUtils.mkdir_p(VCR_DIR)
    filepath = File.join(VCR_DIR, "#{@word}.yml")

    vcr_data = {
      'http_interactions' => [
        {
          'request' => {
            'method' => 'get',
            'uri' => @url,
            'body' => {'encoding' => 'UTF-8', 'string' => ''},
            'headers' => {'User-Agent' => ['Ruby']} # Example header
          },
          'response' => {
            'status' => {'code' => 200, 'message' => 'OK'},
            'headers' => {'Content-Type' => ['text/html; charset=UTF-8']}, # Example header
            'body' => {'encoding' => 'UTF-8', 'string' => html_response_body},
            'http_version' => nil
          },
          'recorded_at' => Time.now.httpdate
        }
      ],
      'recorded_with' => 'WiktionaryScraper' # Custom identifier
    }

    File.write(filepath, vcr_data.to_yaml)
    puts "Saved VCR cassette to #{filepath}"
  end
end