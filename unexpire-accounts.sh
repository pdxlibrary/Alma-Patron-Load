#! /usr/bin/env bash

# Switch accounts to the group indicated in the patron data export.

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

# Sanitize the patron data file
cd $APPHOME
sed -i -e 's/\([0-9]"\)"/\1/g' $config_tempfolder/$config_banner_filename


## Unexpired Patrons
if [[ $config_debug != 0 ]]; then
	echo "Processing unexpirations..."
fi

declare -A affected_users

#todo: make this dynamic
declare -A patron_types
patron_types=(
    ["FACULTY"]="faculty"
    ["EMERITUS"]="emeritus"
    ["GRADASSISTANT"]="gradasst"
    ["GRADUATE"]="grad"
    ["HONOR"]="honors"
    ["UNDERGRADUATE"]="undergrad"
    ["HIGHSCHOOL"]="highschool"
    ["STAFF"]="staff"
)

if [[ $config_debug == 1 ]]; then
        echo "python fetch-analytics-report-data.py -k ${config_alma_analitycs_api_key} -p ${config_alma_analytics_expired_group_members_report_path} -f ${config_alma_analytics_unexpirations_barcode_field}"
fi

# Change groups where appropriate
if [[ $config_debug != 0 ]]; then
        echo "Processing unexpirations..."
fi

python ./fetch-analytics-report-data.py -k ${config_alma_analitycs_api_key} -p ${config_alma_analytics_expired_group_members_report_path} -f ${config_alma_analytics_unexpirations_barcode_field} > $config_tempfolder/$config_alma_expired_patrons_list
for barcode in `cat $config_tempfolder/$config_alma_expired_patrons_list`; do
        echo "Processing ${barcode}..."
	if [ $(grep -ic ${barcode} ${config_tempfolder}/${config_banner_filename}) -gt 0 ]; then 
		zip_code="$(grep ${barcode} ${config_tempfolder}/${config_banner_filename} | awk -F, '{print $12}' | sed -e 's/\"//g' | cut -c1-5)"

		if [[ $zip_code =~ ^[0-9]{5}([-][0-9]{4})?$ ]]; then
			patron_group=${patron_types[$(grep ${barcode} ${config_tempfolder}/${config_banner_filename} | awk -F, '{print $1}' | sed -e 's/\"//g')]}
			if [ $(grep -ic ${zip_code} ${config_tempfolder}/${config_ad_zipcodefilename}) -eq 0 ]; then
				patron_group="${patron_group}-distance"
			fi

			if [[ $config_debug == 0 ]]; then
				python change-patron-group.py -g ${patron_group} -k ${config_alma_analitycs_api_key} ${barcode}
                        else
                                echo "python change-patron-group.py -g ${patron_group} -k ${config_alma_analitycs_api_key} ${barcode}"
			fi
			affected_users[$barcode]=$patron_group
		fi
	fi
done

if [[ $config_debug != 0 ]]; then
	echo "${#affected_users[@]} users were unexpired."
fi

# Send summary of changes
if [[ ${#affected_users[@]} != 0 ]]; then
    declare message_body
    
    for key in "${!affected_users[@]}"; do
        message_body=$(printf "%s\nAssigning patron with barcode %s to group %s.\n" "$message_body" "$key" "${affected_users[$key]}")
    done

    if [[ $config_debug == 0 ]]; then
        printf "%s\n" "${message_body}" | /bin/mail -s "${config_unexpirations_notice_subject}" ${config_unexpirations_notice_recipient}
    else
    	echo "Debug mode. Not sending unexpirations notice."
    	printf "%s\n" "${message_body}" >&2
    fi
fi

if [[ $config_debug != 0 ]]; then
	echo "Finished processing unexpirations."
fi
