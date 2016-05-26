#! /usr/bin/env bash

# Switch accounts to the 'expired patrons' group.

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

# Sanitize the patron data file
cd $APPHOME
sed -i -e 's/\([0-9]"\)"/\1/g' $config_tempfolder/$config_banner_filename


declare -A affected_users
patron_group="${config_expired_patrons_group}"

if [[ $config_debug == 1 ]]; then
        echo "fetch-analytics-report-data.py -k ${config_alma_analitycs_api_key} -p ${config_alma_analytics_expired_patrons_report_path} -f ${config_alma_analytics_report_barcode_field} > $config_tempfolder/$config_alma_to_be_expired_patrons_list"
fi

# Change groups where appropriate
if [[ $config_debug != 0 ]]; then
        echo "Processing expirations..."
fi

python fetch-analytics-report-data.py -k ${config_alma_analitycs_api_key} -p ${config_alma_analytics_expired_patrons_report_path} -f ${config_alma_analytics_report_barcode_field} > $config_tempfolder/$config_alma_to_be_expired_patrons_list
for barcode in `cat $config_tempfolder/$config_alma_to_be_expired_patrons_list`; do
	if [[ $config_debug == 0 ]]; then
                python change-patron-group.py -g ${patron_group} -k ${config_alma_analitycs_api_key} ${barcode}
        else
                echo "python change-patron-group.py -g ${patron_group} -k ${config_alma_analitycs_api_key} ${barcode}"
	fi
	affected_users[$barcode]=$patron_group
done

if [[ $config_debug != 0 ]]; then
        echo "${#affected_users[@]} users were expired."
fi

# Send expirations notice
if [[ ${#affected_users[@]} != 0 ]]; then
    declare message_body
    for key in "${!affected_users[@]}"; do
        message_body=$(printf "%s\nAssigning patron with barcode %s to group %s\n" "$message_body" "$key" "${affected_users[$key]}")
    done
    if [[ $config_debug == 0 ]]; then
        printf "%s\n" "${message_body}" | /bin/mail -s "${config_expirations_notice_subject}" $config_expirations_notice_recipient
    else
    	echo "Debug mode. Not sending expirations notice."
    	printf "%s\n" "${message_body}" >&2
    fi
fi

if [[ $config_debug != 0 ]]; then
        echo "Finished processing expirations."
fi
