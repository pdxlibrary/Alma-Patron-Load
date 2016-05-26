#! /usr/bin/env python
# -*- coding: utf-8 -*-

import requests, sys
from bs4 import BeautifulSoup
from optparse import OptionParser


ALMA_API_BASE_URL='https://api-na.hosted.exlibrisgroup.com'
ALMA_ANALYTICS_API_LIMIT='1000'


def main(argv):
    usage = "usage: %prog [options]"

    parser = OptionParser(usage=usage)
    parser.add_option('-f', '--barcode-field',
                      help='Analytics report barcode field',
                      dest='barcode_field')
    parser.add_option('-k', '--api-key', 
                      help='Alma API key', 
                      dest='api_key')
    parser.add_option('-p', '--analytics-report-path', 
                      help='Path to Alma Analitycs report', 
                      dest='analytics_report_path')

    try:
        (options, args) = parser.parse_args()

        request_url = ALMA_API_BASE_URL + options.analytics_report_path + "&apikey=" + options.api_key + "&limit=" + ALMA_ANALYTICS_API_LIMIT 
        finished = False

        while not finished:
            r = requests.get(request_url)
            soup = BeautifulSoup(r.text, features='xml')
            for barcode in soup.find_all(options.barcode_field):
                print barcode.string
            resume_token = soup.find('ResumptionToken')
            if resume_token is not None:
                request_url = request_url + "&token=" + resume_token.string
            if soup.find('IsFinished').string == 'true':
                    finished = True

    except TypeError:
        parser.print_help()
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)

