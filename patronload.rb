#! /usr/bin/env ruby

require 'optparse'
require 'csv'
require 'net/smtp'
require 'erb'
require 'logger'
require 'date'


# Converts a CSV export from Banner (Student Information System) to a zip archive of Alma-compatible XML files.

# Fields received from the SIS export:
# "patron","per_pidm","id_number","last_name","first_name","middle_name",
# "street_line1","street_line2","street_line3","city_1","state_1","zip_1",
# "phone","alt_phone","email","stu_major","stu_major_desc","orgn_code_home",
# "orgn_desc","empl_expiry_date","coadmit","honor_prog","stu_username","udc_id",

# Arguments
# -i CSV file from the Student Information System (Banner)
# -z Text file containing non-distance ZIP codes. 
#    Format: One ZIP code per line.
# -o Basename for CSV files. 
#    'userdata.xml' will result in 1-userdata.xml, 2-userdata.xml, ...
# -d Enable debug logging (to stdout)

class Patron

  attr_reader :expdate, :first_name, :middle_name, :last_name,
              :status, :patron_type, :username, :barcode, :coadmit_code,
              :address_line1, :address_line2, :address_line3, :city, 
              :zip_code, :start_date, :state, :address_type, :email,
              :email_address_type, :telephone, :telephone_type, :telephone2,
              :telephone2_type, :purge_date, :distance, :honors, :department

  def extract_phone_number(number)
    if number.gsub(/\D/, "").match(/^1?(\d{3})(\d{3})(\d{4})/)
      [$1, $2, $3].join("-")
    else
      nil
    end
  end

  def initialize(row, nondistance_zip_codes)

    # Kluge to replace invalid characters
    row.each do |key|
      unless row[key].nil?
        row[key].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
      end
    end

    @campus_phone_prefix = '503-725-'
    @campus_email_domain = 'pdx.edu'

    @patron_types = Hash.new
    @patron_types = {
      'FACULTY' => 'faculty',
      'EMERITUS' => 'emeritus',
      'GRADASSISTANT' => 'gradasst',
      'GRADUATE' => 'grad',
      'HONOR' => 'honors',
      'UNDERGRADUATE' => 'undergrad',
      'HIGHSCHOOL' => 'highschool',
      'STAFF' => 'staff',
    }

    @coadmits = Hash.new
    @coadmits = {
      "Coadmit - Clackamas CC" => "COAD - CLCC",
      "Coadmit - Mt Hood CC" => "COAD - MHCC",
      "Coadmit - Portland CC" => "COAD - PCC",
      "Coadmit - Chemeketa CC" => "COAD - CHMK CC",
      "Coadmit - Clatsop CC" => "COAD - CCC",
      "Coadmit - Clark College" => "COAD - CLARK",
      "Coadmit - PostBac" => "COAD - PostBac",
    }
    @coadmit_code = @coadmits[row[:coadmit]]

    ## USERNAME    
    @username = row[:stu_username].upcase unless row[:stu_username].nil?

    ## STATISTICAL TYPES
    zipcode = row[:zip_1].chomp[0..4]
    @distance = zipcode == '' || (zipcode =~ /^\d{5}$/ && nondistance_zip_codes.include?(zipcode)) ? false : true

    ## PATRON TYPE
    if @distance
      @patron_type = "#{@patron_types[row[:patron]]}-distance"
    else
      @patron_type = @patron_types[row[:patron]]
    end

    @department = row[:orgn_desc] unless row[:orgn_desc] == '' || (@patron_type != 'faculty' && @patron_type != 'staff')
    @department = @department.gsub(/&/, 'and') unless @department.nil?
    @honors = nil unless row[:patron] == 'HONOR'

    ## EXPIRATION DATE
    @expdate = case @patron_type
    when @patron_type == 'staff'
      if Date.today < Date.parse("#{Date.today.year}-06-01}")
        "#{Date.today.year + 2}0630"
      else
        "#{Date.today.year + 1}0630"
      end
    when @patron_type == 'faculty'
      "#{Date.today.year + 2}0630"
    when @patron_type == 'grad', @patron_type == 'undergrad'
      if Date.today < Date.parse("#{Date.today.year}-03-15") # 1/1 - 3/14
        "#{Date.today.year}1020"
      elsif Date.today < Date.parse("#{Date.today.year}-06-15") # 3/15 - 6/14
        "#{Date.today.year}1020"
      elsif Date.today < Date.parse("#{Date.today.year}-09-01") # 6/15 - 8/31
        "#{Date.today.year.next}0131"
      elsif Date.today < Date.parse("#{Date.today.year}-12-15") # 9/1 - 12/14
        "#{Date.today.year.next}0425"
      else # 12/15 - 12/31
        "#{Date.today.year.next}1020"
      end
    else
      "#{Date.today.year + 2}0630"
    end

    ## PURGE DATE
    @purge_date = Date.parse(@expdate).next_day(180).to_s.gsub(/-/, '') # I know...

    ## BARCODE
    @barcode = row[:id_number]

    ## NAME
    @first_name = row[:first_name].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
    @middle_name = row[:middle_name].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
    @last_name = row[:last_name].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')

    ## ADDRESS
    if @patron_type == 'faculty'
      @address_type = 'work'
    elsif @patron_type.include?('-distance')
      @address_type = 'home'
    else
      @address_type = 'school'
    end

    @address_line1 = row[:street_line1].gsub(/&/, 'and').encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8') || nil
    @address_line2 = row[:street_line2].gsub(/&/, 'and').encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8') || nil unless @address_line2.nil?
    @address_line3 = row[:street_line3].gsub(/&/, 'and').encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8') || nil unless @address_line3.nil?

    @state = row[:state_1].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
    @zip_code = zipcode.encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
    @city = row[:city_1].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')

    ## TELEPHONE
    row[:phone]
    @telephone = (row[:phone] == '' || row[:phone].nil?) ? nil : extract_phone_number(row[:phone])
    unless @telephone.nil?
      @telephone_type = @telephone.include?(@campus_phone_prefix) ? 'office' : 'home'
    end
    
    ## TELEPHONE2
    row[:alt_phone]
    @telephone2 = (row[:alt_phone] == '' || row[:alt_phone].nil?) ? nil : extract_phone_number(row[:alt_phone])
    if @telephone2 == @telephone
      @telephone2 = nil
    end
    unless @telephone2.nil?
      @telephone2_type = @telephone2.include?(@campus_phone_prefix) ? 'office' : 'home'
    end

    ## EMAIL
    @email = String.new(row[:email]) unless row[:email].nil?
    if @email.nil? || @email.include?(@campus_email_domain)
      if @patron_type == 'faculty' || @patron_type == 'staff' || @patron_type == 'emeritus'
        @email_address_type = 'work'
      else
        @email_address_type = 'school'
      end
    else
      @email_address_type = 'personal'     
    end

    @status = 'Active'
    @start_date = Date.today.strftime("%Y%m%d")
  end

end


## Parse command-line arguments
options = {}
options[:debug] = false
opts = OptionParser.new do |parser|
  parser.banner = "Usage: patronload.rb [options]"
  parser.separator ''
  parser.on("-i", "--sis_file FILENAME", "CSV from the Student Information System") do |sis_file|
    options[:sis_file] = sis_file
  end
  parser.on("-o", "--alma_file FILENAME", "Base for the Alma XML filename") do |alma_file|
    options[:alma_file] = alma_file
  end
  parser.on("-z", "--zip_code_file FILENAME", "Non-distance ZIP code file") do |zip_code_file|
    options[:zip_code_file] = zip_code_file
  end
  parser.on("-d", "--debug", "Write debug messages.") do |debug|
    options[:debug] = true
  end
  parser.on_tail("-h", "--help", "Display this screen") do |help|
    puts parser.help
    exit
  end
end


## Validate command-line arguments - I'm probably not using this correctly
opts.parse!(ARGV)
if options[:sis_file].nil? or options[:alma_file].nil? or options[:zip_code_file].nil?
  raise OptionParser::MissingArgument, "\nUse ./patronload.rb -h for an argument list.\n" 
end


## Set logging - the target should probably be configured somewhere else
log = Logger.new(STDERR)
if options[:debug]
  log.level = Logger::DEBUG
else
  log.level = Logger::INFO
end


## Read non-distance zip codes file
@zip_codes = []
begin
  File.open("#{options[:zip_code_file]}").each_line do |line|
    if line.chomp =~ /^[0-9]{5}$/
      @zip_codes.push(line.chomp)
    end
  end
rescue Exception => e
  log.error("Error reading non-distance ZIP code file #{options[:zip_code_file]}\n#{e}")
end


## Read SIS export file
all_patrons = []
CSV.foreach("#{options[:sis_file]}", :headers => true, :header_converters => :symbol, encoding: "ISO-8859-1") do |row|
  all_patrons.push(Patron.new(row, @zip_codes))
end


## Write Alma XML files
log.debug("Writing #{all_patrons.count} patrons to Alma XML file(s).")
xml_file_id = 1
basename = File.basename(options[:alma_file])
dirname = File.dirname(options[:alma_file])


## Alma likes XML files with less than 10000 records. 
all_patrons.each_slice(10000).to_a.each do |patrons|
  log.debug("*** XML FILE #{xml_file_id}: BEGIN ***")
  filename = "#{dirname}/#{xml_file_id}-#{basename}"
  begin
    template = ERB.new(File.read('templates/userdata.xml.erb'), nil, '-')
    @patrons = patrons
    xml = template.result(binding)
    log.debug("Opening #{filename} for writing.")
    File.open(filename, 'w+') do |file|
      file.puts xml
    end
  rescue Exception => e
    log.error("Unable to open #{filename} for writing.\nERROR: #{e}")
  end
  log.debug("*** XML FILE #{xml_file_id}: END   ***")
  xml_file_id = xml_file_id + 1
end
