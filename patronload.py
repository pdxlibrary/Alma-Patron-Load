#! /usr/bin/env python

import csv
import datetime
import getopt
import logging
#import os
import sys
import re

#from collections import OrderedDict
from datetime import date

# patron|per_pidm|id_number|last_name|first_name|middle_name|
# street_line1|street_line2|street_line3|city_1|state_1|zip_1|phone|alt_phone|email|
# stu_major|stu_major_desc|orgn_code_home|orgn_desc|coadmit|honor_prog|
# stu_username|udc_id|pref_first_name|termination_dt|

PATRON_DATA_FILE = "tmp/patrondata.csv"
DEPARTMENTS_FILE = "tmp/departments.csv"
ZIP_CODES_FILE = "tmp/non-distance-zipcodes.txt"


class Patron:
    campus_phone_prefix = '503-725-'
    campus_email_domain = 'pdx.edu'
    patron_types = {
        'FACULTY': 'faculty',
        'EMERITUS': 'emeritus',
        'GRADASSISTANT': 'gradasst',
        'GRADUATE': 'grad',
        'HONOR': 'honors',
        'UNDERGRADUATE': 'undergrad',
        'HIGHSCHOOL': 'highschool',
        'STAFF': 'staff'
    }
    coadmits = {
        "Coadmit - Clackamas CC": "COAD - CLCC",
        "Coadmit - Mt Hood CC": "COAD - MHCC",
        "Coadmit - Portland CC": "COAD - PCC",
        "Coadmit - Chemeketa CC": "COAD - CHMK CC",
        "Coadmit - Clatsop CC": "COAD - CCC",
        "Coadmit - Clark College": "COAD - CLARK",
        "Coadmit - PostBac": "COAD - PostBac"
    }

    @staticmethod
    def get_expiration_date(patron_type):
        if patron_type in ['staff', 'staff-distance']:
            if date.today() < datetime.datetime.strptime(str(date.today().year) + "0601", "%Y%m%d").date():
                expdate = datetime.datetime.strptime(str(date.today().year + 2) + "0630")
            else:
                expdate = datetime.datetime.strptime(str(date.today().year + 1) + "0630", "%Y%m%d")
        elif patron_type in ['faculty', 'gradasst', 'emeritus',
                             'faculty-distance', 'gradasst-distance', 'emeritus-distance']:
            expdate = datetime.datetime.strptime(str(date.today().year + 1) + "0630", "%Y%m%d")
        elif patron_type in ['grad', 'undergrad', 'honors', 'highschool',
                             'grad-distance', 'undergrad-distance', 'highschool-distance']:
            # 1/1 - 3/14
            if date.today() < datetime.datetime.strptime(str(date.today().year) + "0315", "%Y%m%d").date():
                expdate = datetime.datetime.strptime(str(date.today().year) + "1020", "%Y%m%d")
            # 3/15 - 6/14
            elif date.today() < datetime.datetime.strptime(str(date.today().year) + "0615", "%Y%m%d").date():
                expdate = datetime.datetime.strptime(str(date.today()) + "1020", "%Y%m%d")
            # 6/15 - 8/31
            elif date.today() < datetime.datetime.strptime(str(date.today().year) + "0901", "%Y%m%d").date():
                expdate = datetime.datetime.strptime(str(date.today().year + 1) + "0131", "%Y%m%d")
            # 9/1 - 12/14
            elif date.today() < datetime.datetime.strptime(str(date.today().year) + "1215", "%Y%m%d").date():
                expdate = datetime.datetime.strptime(str(date.today().year + 1) + "0425", "%Y%m%d")
            # 12/15 - 12/31
            else:
                expdate = datetime.datetime.strptime(str(date.today().year + 1) + "1020", "%Y%m%d")
        else:
            expdate = datetime.datetime.strptime(str(date.today().year + 2) + "0630", "%Y%m%d")

        return expdate.date()

    def __init__(self, patron_data, is_distance=False):
        if patron_data['pref_first_name']:
            self.first_name = patron_data['pref_first_name']
        else:
            self.first_name = patron_data['first_name']

        self.barcode = patron_data['id_number']
        self.middle_name = patron_data['middle_name']
        self.last_name = patron_data['last_name']

        if is_distance:
            self.patron_type = self.patron_types[patron_data['patron']] + "-distance"
        else:
            self.patron_type = self.patron_types[patron_data['patron']]

        if patron_data['coadmit']:
            self.coadmit_code = self.coadmits[patron_data['coadmit']]
        self.address_line1 = patron_data['street_line1']  #validate
        self.city = patron_data['city_1']  # validate
        self.state = patron_data['state_1']  # validate
        self.zip_code = patron_data['zip_1'][:5]  # validate

        if self.patron_type == 'faculty':
            self.address_type = 'work'
        elif is_distance:
            self.address_type = 'home'
        else:
            self.address_type = 'school'

        self.expdate = self.get_expiration_date(self.patron_type)
        self.purge_date = self.expdate + datetime.timedelta(days=180)

        self.email = patron_data['email']
        if self.email.endswith(self.campus_email_domain):
            self.email_address_type = 'work'
        else:
            self.email_address_type = 'personal'

        # Sanitize phone numbers by stripping non-numeric characters and adding hyphens to the first 10 numbers
        phone_numbers = re.compile(r'[^\d]+')
        if patron_data['phone']:
            clean_phone = phone_numbers.sub("", patron_data['phone'])
            self.telephone = '-'.join([clean_phone[:3], clean_phone[3:6], clean_phone[6:10]])
            if self.campus_phone_prefix in self.telephone:
                self.telephone_type = 'office'
            else:
                self.telephone_type = 'home'
        if patron_data['alt_phone']:
            clean_phone = phone_numbers.sub("", patron_data['alt_phone'])
            self.telephone2 = '-'.join([clean_phone[:3], clean_phone[3:6], clean_phone[6:10]])
            if self.campus_phone_prefix in self.telephone2:
                self.telephone2_type = 'office'
            else:
                self.telephone2_type = 'home'

        if patron_data['stu_username'] == '':
            raise ValueError('Username missing for patron record %s' % self.barcode)
        else:
            self.username = patron_data['stu_username']

        if patron_data['orgn_desc']:
            self.department_code = patron_data['orgn_desc'].split(" ")[0]
        elif patron_data['stu_major'] is '0000':
            logging.warning("Both department and major missing in patron record %s !!!" % patron_data['id_number'])
        elif patron_data['stu_major']:
            self.department_code = patron_data['stu_major']
            self.department_name = patron_data['stu_major_desc']

        self.start_date = datetime.date.today().strftime("%Y%m%d")

options = {
    u'-h, --help': u'Display help',
    u'-v, --verbose': u'Verbose mode',
}


def usage():
    print(u'\nUsage: patronload.py [options]\n')
    print(u'Options:')
    for key, value in sorted(options.iteritems()):
        print(u'\t%s\t%s' % (key, value))
    print(u'\n')


def load_department_codes_file(file_path):
    file_contents = {}

    csv_file = open(file_path)
    csv_reader = csv.DictReader(csv_file, delimiter=",")
    for row in csv_reader:
        file_contents[row['code']] = row['label']
    csv_file.close()

    return file_contents


def load_zip_codes_file(file_path):
    text_file = open(file_path)
    file_contents = text_file.read().splitlines()
    text_file.close()

    return file_contents


def load_patron_data_file(file_path, non_distance_zip_codes):
    patron_data = {}

    csv_file = open(file_path)
    csv_reader = csv.DictReader(csv_file, delimiter="|", quotechar='"')
    for row in csv_reader:
        distance = False
        if row['zip_1'] and row['zip_1'][:5] not in non_distance_zip_codes:
            distance = True
        try:
            patron_data[row['id_number']] = Patron(row, distance)
        except ValueError as error:
            logging.warning(error.args)

    return patron_data


def find_new_department_codes(department_codes, patron_data):
    new_department_codes = []

    for barcode, patron in patron_data.items():
        if hasattr(patron, 'department_code'):
            if patron.department_code not in department_codes and patron.department_code not in new_department_codes:
                if hasattr(patron, 'department_name'):
                    logging.debug("New department code %s \"%s\" found in record %s" % (patron.department_code,
                                                                                        patron.department_name,
                                                                                        patron.barcode))
                else:
                    logging.debug("New department code %s found in record %s" % (patron.department_code,
                                                                                 patron.barcode))
                new_department_codes.append(patron.department_code)

    return new_department_codes


def main():
    try:
        opts, args = getopt.gnu_getopt(sys.argv[1:], 'hv', ['help', 'verbose'])
    except getopt.GetoptError as error:
        print(str(error))
        usage()
        sys.exit(2)

    option_missing = False
    verbose = False

    for opt, arg in opts:
        if opt in ('-h', '--help'):
            usage()
            sys.exit(2)
        if opt in ('v', '--verbose'):
            verbose = True

    if option_missing:
        usage()
        sys.exit(2)

    if verbose:
        logging.info("Verbose mode")

    department_codes = load_department_codes_file(DEPARTMENTS_FILE)
    non_distance_zip_codes = load_zip_codes_file(ZIP_CODES_FILE)
    patron_data = load_patron_data_file(PATRON_DATA_FILE, sorted(non_distance_zip_codes))

    if verbose:
        for barcode, patron in patron_data.items():
            print("\nNew Record")
            print("\tBarcode: %s" % barcode)
            print("\tFirst name: %s" % patron.first_name)
            if hasattr(patron, 'middle_name'):
                print("\tMiddle name: %s" % patron.middle_name)
            print("\tLast name: %s" % patron.last_name)
            print("\tExpiration Date: %s" % patron.expdate)
            print("\tPurge Date: %s" % patron.purge_date)
            if hasattr(patron, 'address_line1'):
                print("\tAddress: %s " % patron.address_line1)
            if hasattr(patron, 'city'):
                print("\tCity: %s" % patron.city)
            if hasattr(patron, 'state'):
                print("\tState: %s" % patron.state)
            if hasattr(patron, 'zip_code'):
                print("\tZIP code: %s" % patron.zip_code)
            if hasattr(patron, 'address_type'):
                print("\tAddress type: %s" % patron.address_type)
            if hasattr(patron, 'email'):
                print("\tEmail: %s" % patron.email)
            if hasattr(patron, 'email_address_type'):
                print("\tEmail: %s" % patron.email_address_type)
            if hasattr(patron, 'telephone'):
                print("\tPhone: %s" % patron.telephone)
            if hasattr(patron, 'telephone_type'):
                print("\tPhone: %s" % patron.telephone_type)
            if hasattr(patron, 'telephone2'):
                print("\tPhone: %s" % patron.telephone2)
            if hasattr(patron, 'telephone2_type'):
                print("\tPhone: %s" % patron.telephone2_type)
            if hasattr(patron, 'coadmit_code'):
                print("\tCoadmit code: %s" % patron.coadmit_code)
            if hasattr(patron, 'telephone2'):
                print("\tAlt phone: %s" % patron.telephone2)
            if hasattr(patron, 'username'):
                print("\tPhone: %s" % patron.username)
            if hasattr(patron, 'department_code'):
                print("\tDepartment code: %s" % patron.department_code)
            if hasattr(patron, 'patron_type'):
                print("\tPatron type: %s" % patron.patron_type)

    new_department_codes = find_new_department_codes(department_codes, patron_data)
    print("%s new department codes found." % len(new_department_codes))


if __name__ == '__main__':
    main()
