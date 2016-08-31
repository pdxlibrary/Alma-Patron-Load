#! /usr/bin/env ruby

require 'optparse'
require 'csv'
require 'net/smtp'
require 'erb'
require 'logger'
require 'date'
require 'net/smtp'

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
              :telephone2_type, :purge_date, :distance, :honors, :department_code

  def extract_phone_number(number)
    if number.gsub(/\D/, "").match(/^1?(\d{3})(\d{3})(\d{4})/)
      [$1, $2, $3].join("-")
    else
      nil
    end
  end

  def initialize(row, nondistance_zip_codes)

    # Kluge to replace invalid characters
    row.each do |k, v|
      unless v.nil?
        row[k] = v.encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
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
    if row[:zip_1].nil?
      zipcode = ''
    else
      zipcode = row[:zip_1].chomp[0..4]
    end
    @distance = zipcode == '' || (zipcode =~ /^\d{5}$/ && nondistance_zip_codes.include?(zipcode)) ? false : true

    ## PATRON TYPE
    if @distance
      @patron_type = "#{@patron_types[row[:patron]]}-distance"
    else
      @patron_type = @patron_types[row[:patron]]
    end

    department = row[:orgn_desc] unless row[:orgn_desc] == '' or row[:orgn_desc].nil? 
    department = department.gsub(/&/, 'and') unless department.nil?
    @department_code, *rest = department.split(/ /) unless department.nil?


    @honors = nil unless row[:patron] == 'HONOR'

    ## EXPIRATION DATE
    if(@patron_type.match('staff'))
      if Date.today < Date.parse("#{Date.today.year}-06-01}")
        @expdate = "#{Date.today.year + 2}-06-30"
      else
        @expdate = "#{Date.today.year + 1}-06-30"
      end
    elsif @patron_type.match('faculty') or @patron_type.match('gradasst') or @patron_type.match('emeritus')
      @expdate = "#{Date.today.year + 2}-06-30"
    elsif @patron_type.match('grad') or @patron_type.match('undergrad') or @patron_type.match('honors') or @patron_type.match('highschool')
      if Date.today < Date.parse("#{Date.today.year}-03-15") # 1/1 - 3/14
        @expdate = "#{Date.today.year}-10-20"
      elsif Date.today < Date.parse("#{Date.today.year}-06-15") # 3/15 - 6/14
        @expdate = "#{Date.today.year}-10-20"
      elsif Date.today < Date.parse("#{Date.today.year}-09-01") # 6/15 - 8/31
        @expdate = "#{Date.today.year.next}-01-31"
      elsif Date.today < Date.parse("#{Date.today.year}-12-15") # 9/1 - 12/14
        @expdate = "#{Date.today.year.next}-04-25"
      else # 12/15 - 12/31
        @expdate = "#{Date.today.year.next}-10-20"
      end
    else
      @expdate = "#{Date.today.year + 2}-06-30"
    end

    ## PURGE DATE
    @purge_date = Date.parse(@expdate).next_day(180).to_s # I know...

    ## BARCODE
    @barcode = row[:id_number]

    ## NAME
    if row.has_key?(:pref_first_name) and !row[:pref_first_name].nil? and row[:pref_first_name] != ''
      @first_name = row[:pref_first_name].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
    else
      @first_name = row[:first_name].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
    end
    if !row[:middle_name].nil?
      @middle_name = row[:middle_name].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
    end
    @last_name = row[:last_name].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')

    ## ADDRESS
    if @patron_type == 'faculty'
      @address_type = 'work'
    elsif @patron_type.include?('-distance')
      @address_type = 'home'
    else
      @address_type = 'school'
    end
    
    if row[:street_line1].nil?
      @address_line1 = ''
    else
      @address_line1 = row[:street_line1].gsub(/&/, 'and').gsub(/(?<!^|,)"(?!,|$)/, '_').encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8') || nil
    end
    @address_line2 = row[:street_line2].gsub(/&/, 'and').gsub(/(?<!^|,)"(?!,|$)/, '_').encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8') || nil unless @address_line2.nil?
    @address_line3 = row[:street_line3].gsub(/&/, 'and').gsub(/(?<!^|,)"(?!,|$)/, '_').encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8') || nil unless @address_line3.nil?

    if row[:state_1].nil?
      @state = ''
    else
      @state = row[:state_1].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
    end

    if row[:zip_1].nil?
      @zip_code = ''
    else
      @zip_code = zipcode.encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
    end
    if row[:city].nil?
      @city = ''
    else
      @city = row[:city_1].encode!('ISO-8859-1', "binary", :invalid => :replace, :undef => :replace).force_encoding('UTF-8')
    end

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
  parser.on("-e", "--dept_file FILENAME", "Departments to labels file") do |dept_file|
    options[:dept_file] = dept_file
  end
  parser.on("-d", "--debug", "Write debug messages.") do |debug|
    options[:debug] = true
  end
  parser.on("-s", "--suppress_email", "Suppress email notices.") do |suppress_email|
    options[:suppress_email] = true
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
CSV.foreach("#{options[:sis_file]}", :headers => true, :header_converters => :symbol, encoding: "ISO-8859-1", :col_sep => "|") do |row|
  all_patrons.push(Patron.new(row, @zip_codes))
end

departments = {}
CSV.foreach("#{options[:dept_file]}", :headers => true, :header_converters => :symbol, :converters => :all) do |row|
  departments[row.fields[0]] = Hash[row.headers[1..-1].zip(row.fields[1..-1])]
end

## Write Alma XML files
log.debug("Writing #{all_patrons.count} patrons to Alma XML file(s).")
xml_file_id = 1
basename = File.basename(options[:alma_file])
dirname = File.dirname(options[:alma_file])

## Alma likes XML files with 10000 records or fewer. 
all_patrons.each_slice(10000).to_a.each do |patrons|
  log.debug("*** XML FILE #{xml_file_id}: BEGIN ***")
  filename = "#{dirname}/#{xml_file_id}-#{basename}"

  patrons.each do |patron|
    if patron.first_name == patron.last_name
      log.warn("First name - last name issue with #{patron.barcode}")
    end
    if !patron.department_code.nil? and !departments.has_key?(patron.department_code)
      log.warn("Department code #{patron.department_code} was not found in existing departments list")
      if !options[:suppress_email]
        message_to = "libsys@pdx.edu"
        message_from = "libsys@pdx.edu"
        message_cc = "herc@pdx.edu"
        Net::SMTP.start('mailhost.pdx.edu', 25) do |smtp|
          smtp.open_message_stream(message_from, message_to) do |f|
            f.puts "From: #{message_from}"
            f.puts "To: #{message_to}"
            f.puts "Cc: #{message_cc}"
            f.puts "Subject: Unrecognized department code"
            f.puts
            f.puts "An unrecognized department code was encountered in today\'s patron load. "
            f.puts "Code Found: #{patron.department_code}"
            f.puts "Affected Patron ID: #{patron.barcode}"
          end
        end
      else
        log.debug("An unrecognized department code was encountered: #{patron.department_code} in patron id #{patron.barcode}")
      end
    end
  end

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
