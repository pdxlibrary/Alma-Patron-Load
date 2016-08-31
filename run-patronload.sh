#! /usr/bin/env bash

# Run the patron load.

APPHOME=${PWD}

## Load process configuration files
. config/patronload.config

if [ ! -d $config_tempfolder ]; then
	mkdir $config_tempfolder
fi

# Retrieve patron data file from the Banner SFTP server
# sshpass is not ideal, but key-based ssh auth wasn't a possibility
cd $config_tempfolder
sshpass \
	-p $config_banner_sftppass sftp -oStrictHostKeyChecking=no -oBatchMode=no -b - \
	$config_banner_sftpuser@$config_banner_sftphost << EOF
	cd $config_banner_path
	get $config_banner_filename	
	bye
EOF

# Retrieve the non-distance ZIP codes file from DFS
smbclient -U $config_ad_user -c "cd $config_ad_path; get $config_ad_zipcodefilename; get $config_ad_deptcodefilename; exit" //$config_ad_fileserver/$config_ad_share "$config_ad_pass"

#exit

# Sanitize the patron data file
cd $APPHOME
sed -i -e 's/\([0-9]"\)"/\1/g' $config_tempfolder/$config_banner_filename
sed -i -e 's/[[:blank:]]*$//g' $config_tempfolder/$config_banner_filename # remove whitespace from end of line
sed -i -e 's/","/|/g' $config_tempfolder/$config_banner_filename # convert "," to |
sed -i -e 's/"//g' $config_tempfolder/$config_banner_filename # remove " from line

## Patron load - Generate Alma XML files
if [[ $config_debug != 0 ]]; then
        echo "Running the patron load (`date`)..."
fi
~/.rbenv/shims/ruby patronload.rb -i "$config_tempfolder/$config_banner_filename" \
                                  -e "$config_tempfolder/$config_ad_deptcodefilename" \
                                  -o "$config_tempfolder/$config_xmlfilenamebase" \
                                  -z "$config_tempfolder/$config_ad_zipcodefilename"

# Generate the ZIP file in the SFTP location
cd $config_tempfolder
zip -q $config_sftplocation/$config_zipfilename *-${config_xmlfilenamebase}

# Archive the files used for this load
zip $config_archivelocation/$config_archivefilename $config_ad_zipcodefilename $config_banner_filename

if [[ $config_debug != 0 ]]; then
        echo "Finished patron load (`date`)."
fi

# Clean up
cd $APPHOME
if [[ $config_debug == 0 ]]; then
        rm $config_tempfolder/*
fi
