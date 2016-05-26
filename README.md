# Alma Patron Management

These are scripts used to manage patron records in Alma. 


## Alma Patron Load

This is a big, messy script that converts a CSV export from Banner (Student Information System) to a 
zip archive of Alma-compatible XML files. 

Developed using Ruby 2.0.0-p353 and its standard library. 

### Process

 0. Retrieve CSV export of user data from the Banner SFTP server.
 0. Retrieve the list of local ZIP codes from the library fileserver.
 0. Generate Alma XML files, maximum of 20000 records each, using a template.
 0. Create a ZIP archive of the XML files and transfer it to the library
    SFTP server for retrieval by Alma.

### Example

```ruby patronload.rb -i file_from_sis.csv -o userdata.xml -z non_distance_zipcodes.txt```

Alternatively, use the included wrapper script.

```./run-patronload.sh```


## Alma Patron Expirations

```./expire-accounts.sh```

### Process

 0. Retrieve CSV export of user data from the Banner SFTP server.
 0. Use the Alma Analytics API to retrieve a list of user accounts with expiration dates
    before today.
 0. Iterate through the list of records, changing the accounts to the 'expired patrons' group.
 0. Send a report of the changes made by this process.


## Alma Patron Unexpirations

```./unexpire-accounts.sh```

### Process

 0. Retrieve CSV export of user data from the Banner SFTP server.
 0. Retrieve the list of local ZIP codes from the library fileserver.
 0. Use the Alma Analytics API to retrieve a list of expired user accounts.
 0. Iterate through the list of expired user accounts. If the primary identifier
    matches one in the Banner export, change its group appropriately.
 0. Send a report of the changes made by this process.


