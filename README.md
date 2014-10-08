# Shared ILS Patron Load

This is a big, messy script that converts a CSV export from Banner (Student Information System) to a zip archive of Alma-compatible XML files.

Developed using Ruby 2.0.0-p353 and its standard library. No extra gems are required for this to function. 


## Arguments

 - -d: Print debug messages.
 - -i: CSV file from the Student Information System. Format is defined in the script header.
 - -o: Base for CSV filenames.  
       Using 'userdata.xml' will result in 1-userdata.xml, 2-userdata.xml, ...  
       Similarly 'output_files/userdata.xml' will result in output_files/1-userdata.xml, ...  
 - -z: Text file containing local (non-distance) ZIP codes. One per line.


## Example

```ruby patronload.rb -i file_from_sis.csv -o userdata.xml -z non_distance_zipcodes.txt```
