require 'nokogiri'
require 'uri'
require 'net/http' # Added for HTTP requests
require 'yaml'       # For YAML serialization
require 'fileutils'  # For directory creation
require 'time'       # For Time.now.httpdate
require 'zlib'       # For gzip decompression
require 'stringio'   # For StringIO

class WiktionaryScraper # Renamed from ProductScraper
  VCR_DIR = 'vcr_cassettes'.freeze

  # Removed PUPPETEER_ARGS and TIMEOUT_PAGE_LOAD

  def initialize(url)
    @url = url
    parsed_uri = URI.parse(url)
    @word = parsed_uri.path.split('/').last # Extract word from URL
    validate_url(parsed_uri) # Pass parsed URI
  end

  # Reinstated scrape method
  def scrape
    html_content = fetch_html
    parse_html(html_content)
  end

  # Added save_vcr as a separate action method
  def save_vcr
    html_content = fetch_html # Fetch HTML internally

    FileUtils.mkdir_p(VCR_DIR)
    # Sanitize filename (basic example)
    sanitized_word = @word.gsub(/[^0-9a-z_.-]/i, '_')
    filepath = File.join(VCR_DIR, "#{sanitized_word}.yml")

    vcr_data = {
      'http_interactions' => [
        {
          'request' => {
            'method' => 'get',
            'uri' => @url,
            'body' => {'encoding' => 'UTF-8', 'string' => ''},
            # Mimic a common browser User-Agent
            'headers' => {
              'User-Agent' => ['Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36'],
              'Accept' => ['text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9'],
              'Accept-Encoding' => ['gzip, deflate, br'], # VCR usually handles decoding
              'Accept-Language' => ['en-US,en;q=0.9']
            }
          },
          'response' => {
            'status' => {'code' => 200, 'message' => 'OK'},
            # Use realistic headers (might need adjustment based on actual Wiktionary responses)
            'headers' => {
              'Content-Type' => ['text/html; charset=UTF-8'],
              # Note: We save the *decompressed* body, so we don't list Content-Encoding here in the saved cassette
              # 'Content-Encoding' => ['gzip'], # Often compressed
              'Server' => ['nginx'], # Example
              'Date' => [Time.now.httpdate],
              # Add other relevant headers if needed e.g. Cache-Control, ETag etc.
            },
            # Store the *decompressed* raw body
            'body' => {'encoding' => 'UTF-8', 'string' => html_content},
            'http_version' => nil # VCR often sets this
          },
          'recorded_at' => Time.now.httpdate
        }
      ],
      'recorded_with' => 'WiktionaryScraper' # Identify our scraper
    }

    File.write(filepath, vcr_data.to_yaml)
    puts "Saved VCR cassette to #{filepath}"
  rescue => e
    puts "Error saving VCR cassette for #{@word}: #{e.message}"
    # Optionally re-raise or handle differently
  end

  private

  def validate_url(uri) # Accept parsed URI
    # Use the passed uri object directly
    raise ArgumentError, "Invalid URL: #{@url}" unless @url && uri.is_a?(URI::HTTP) && uri.host&.include?('wiktionary.org')
  rescue URI::InvalidURIError
    raise ArgumentError, "Invalid URL: #{@url}"
  end

  def fetch_html # Replaced Puppeteer logic
    uri = URI.parse(@url)
    # Prepare request with headers
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    request = Net::HTTP::Get.new(uri.request_uri)
    # Use the same headers as defined in save_vcr for consistency
    request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36'
    request['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9'
    request['Accept-Encoding'] = 'gzip, deflate, br' # Request compression
    request['Accept-Language'] = 'en-US,en;q=0.9'

    response = http.request(request)

    # Handle potential compression
    body = case response['content-encoding']&.downcase
           when 'gzip'
             Zlib::GzipReader.new(StringIO.new(response.body)).read
           when 'deflate'
             Zlib::Inflate.new.inflate(response.body)
           # Add case for 'br' (brotli) if needed, requires 'brotli' gem
           else
             response.body
           end

    raise "Failed to fetch URL: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)
    body.force_encoding('UTF-8') # Ensure UTF-8
  rescue Zlib::Error => e # Catch Zlib errors more broadly
    puts "Error decompressing response for #{@url}: #{e.message}"
    # Return the raw body if decompression fails, might be unreadable
    response.body.force_encoding('UTF-8')
  rescue Net::HTTPExceptions => e # Catch network errors
     puts "HTTP Error fetching #{@url}: #{e.message}"
     raise # Re-raise HTTP errors
  end

  # Reinstated parse_html method
  private def parse_html(html_content)
    doc = Nokogiri::HTML(html_content)

    # Find the English language section first
    english_section = doc.at_xpath("//h2[@id='English']")
    unless english_section
      puts "English section not found for #{@word}."
      return { word: @word, error: "English section not found" } # Return word and error
    end

    # Find the parent div of the H2, which should be mw-heading
    heading_div = english_section.parent
    unless heading_div && heading_div.name == 'div' && heading_div['class']&.include?('mw-heading')
      puts "ERROR: Could not find parent heading div for English H2."
      return { word: @word, error: "Could not structure around English H2" }
    end

    # Search within the English section for relevant subsections, STARTING AFTER the H2's div
    current_node = heading_div.next_element
    etymology = nil
    pronunciation_details = {}
    definitions_map = {}
    synonyms_map = {} # Initialize synonyms map

    while current_node && current_node.name != 'h2' # Stop at the next language section
      # Check if the current node is a heading div
      if current_node.name == 'div' && current_node['class']&.include?('mw-heading')
        h3_node = current_node.at_css('h3')
        h4_node = current_node.at_css('h4') # Check for h4 as well for synonyms etc.

        if h3_node
          heading_id = h3_node['id']
          # puts "--- Found H3: #{heading_id}"

          case heading_id
          when 'Etymology'
            # Etymology is typically the paragraph(s) following the heading div
            etymology_p = current_node.xpath("./following-sibling::p[1]")
            etymology = etymology_p.text.strip if etymology_p
          when 'Pronunciation'
            # Pronunciation details often follow in a UL after the heading div
            pronunciation_ul = current_node.xpath("./following-sibling::ul[1]")
            if pronunciation_ul
              ipa_node = pronunciation_ul.at_css("span.IPA")
              pronunciation_details[:ipa] = ipa_node.text.strip if ipa_node
              # Look for audio source within the UL
              audio_node = pronunciation_ul.at_css("source[type='audio/ogg'], source[type='audio/mpeg']") # Look for ogg or mp3
              if audio_node && audio_node['src']
                 audio_src = audio_node['src']
                 audio_url = audio_src.start_with?('//') ? "https:" + audio_src : audio_src
                 audio_url = URI.join(@url, audio_url).to_s unless audio_url.start_with?('http')
                 pronunciation_details[:audio_url] = audio_url
              end
            end
          when 'Noun', 'Verb', 'Adjective', 'Adverb' # Handle common parts of speech
            part_of_speech = heading_id.downcase.to_sym
            definitions_map[part_of_speech] = []

            # Definitions are usually in an OL following the heading div or a P tag
            definitions_ol = current_node.xpath("./following-sibling::ol[1]")
            if definitions_ol
              definitions_ol.css('li').each do |li|
                temp_li = li.dup
                temp_li.css('dl, ul.usage-examples').remove
                definition_text = temp_li.text.strip.gsub(/\s+/, ' ').strip
                definitions_map[part_of_speech] << definition_text unless definition_text.empty?
              end
            end
          # NOTE: Synonyms are now handled below based on h4
          end
        elsif h4_node # Check for H4 headings (like Synonyms)
          heading_id = h4_node['id']
          # puts "--- Found H4: #{heading_id}"
          if heading_id == 'Synonyms' && definitions_map.any? # Ensure we have a part of speech context
            # Assume synonyms belong to the last found part of speech
            last_pos = definitions_map.keys.last
            if last_pos
              # Synonyms might be in a DL or UL following the h4 div
              synonyms_dl = current_node.xpath("./following-sibling::dl[1]")
              synonyms_ul = current_node.xpath("./following-sibling::ul[1]")

              synonyms_list = []
              if synonyms_dl
                # Example: <dl><dd>(sense): <a...>sidekick</a></dd></dl>
                synonyms_list = synonyms_dl.css('dd a').map { |a| a.text.strip }.reject(&:empty?)
              elsif synonyms_ul
                # Example: <ul><li><span><a>...</a></span></li></ul>
                synonyms_list = synonyms_ul.css('li > span > a, li > a').map { |a| a.text.strip }.reject(&:empty?)
              end
              synonyms_map[last_pos] = synonyms_list unless synonyms_list.empty?
            end
          end
        end
      end
      current_node = current_node.next_element
      # puts "Next node: #{current_node.name}" if current_node # Debug: print next node name
    end

    result = {
      word: @word, # Add the word itself
      etymology: etymology,
      pronunciation: pronunciation_details,
      definitions: definitions_map, # Use the map
    }
    result[:synonyms] = synonyms_map unless synonyms_map.empty? # Add synonyms map if it contains data
    result
  end

end