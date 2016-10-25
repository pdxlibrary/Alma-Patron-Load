# Alma Patron Management

These are scripts used to manage patron records in Alma. 

Requirements: Python 2.7


### Process

 0. Retrieve CSV export of user data from the Banner SFTP server.
 0. Retrieve the list of local ZIP codes from the library fileserver.
 0. Retrieve the CSV file that maps Alma department codes to department names.
 0. Use the Alma User API to expire accounts based on results in Users to Expire analysis.
 0. Generate Alma XML files, maximum of 20000 records each, using a template.
 0. Generate a list of users with statistical groups or account types that need changed.
 0. Use the Alma User API to reassign groups in the previous step. (disabled for now)
 0. Use the Alma User API to reassign user groups from expired based on the results in 
    Users to Unexpire analysis. 
 0. Create a zip archive of the XML files and transfer it to the library
    SFTP server for retrieval by Alma.
 0. Send a notice of any new department codes that appeared in the Banner export.
 0. Send a report of the changes made and errors produced by this process.


### Alma Analytics Reports

 * Users to Expire

    User Group Code is equal to / is in expired  
    AND  
    Expiry Date is less than or equal to CURDATE()  
    AND  
    Identifier Type is equal to / is in University ID  

 * Users to Unexpire

    User Group Code is equal to / is in expired  
    AND  
    Expiry Date is greater than CURDATE()  
    AND  
    Identifier Type is equal to / is in University ID  
    

### Example

  ```
  ./expire-accounts.sh
  ./run-patronload.sh
  ./unexpire-accounts.sh
  ```

### Deployment

  * The deployment process is based on Fabric. Send the role to the process using the '-R' option.

  * Deploy to the production server (libsrv9)

     ```
     fab -R production deploy
     ```

  * Deploy to the testing server (deneb)

     ```
     fab -R testing deploy
     ```

