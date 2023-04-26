#!/usr/bin/env python
# coding: utf-8

#Note: This can be easily modified to collect whatever data you want to collect from servers and fabric interconnects in Intersight

# Modify the api_key and key location below
key_id = "YourAPIKeyIDGoesHere"
api_secret_file = "C:\Path\To\Your\SecretAPIKey.txt"

# Import needed Python modules
import csv
import pandas as pd
import sys
import json
import re
import csv
import os
import intersight
from intersight.api import compute_api
from intersight.api import network_api

# Name of export file 
export_file_servers = 'server_datafile.csv'
export_file_fi = 'fi_datafile.csv'

# Define function for connecting securely to Intersight
def get_api_client(key_id, api_secret_file, endpoint="https://intersight.com"):
    with open(api_secret_file, 'r') as f:
        api_key = f.read()

    if re.search('BEGIN RSA PRIVATE KEY', api_key):
        # API Key v2 format
        signing_algorithm = intersight.signing.ALGORITHM_RSASSA_PKCS1v15
        signing_scheme = intersight.signing.SCHEME_RSA_SHA256
        hash_algorithm = intersight.signing.HASH_SHA256

    elif re.search('BEGIN EC PRIVATE KEY', api_key):
        # API Key v3 format
        signing_algorithm = intersight.signing.ALGORITHM_ECDSA_MODE_DETERMINISTIC_RFC6979
        signing_scheme = intersight.signing.SCHEME_HS2019
        hash_algorithm = intersight.signing.HASH_SHA256

    configuration = intersight.Configuration(
        host=endpoint,
        signing_info=intersight.signing.HttpSigningConfiguration(
            key_id=key_id,
            private_key_path=api_secret_file,
            signing_scheme=signing_scheme,
            signing_algorithm=signing_algorithm,
            hash_algorithm=hash_algorithm,
            signed_headers=[
                intersight.signing.HEADER_REQUEST_TARGET,
                intersight.signing.HEADER_HOST,
                intersight.signing.HEADER_DATE,
                intersight.signing.HEADER_DIGEST,
            ]
        )
    )

    return intersight.ApiClient(configuration)
    print(configuration)

# Connect to Intersight as an API client
api_client = get_api_client(key_id, api_secret_file)

# Call the compute API for Intersight
api_instance = compute_api.ComputeApi(api_client)

# Retrieve json formatted data on all servers
def get_server_data():
    global server_data
    global server_inventory
    global server_count
    server_data = api_instance.get_compute_physical_summary_list()
    # Handling error scenario if it does not return any entry.
    if not server_data.results:
        raise NotFoundException(reason="The response does not contain any servers.")
    #Get the count of servers
    server_inventory = server_data.results
    server_count = len(server_inventory)
    print("There are " + str(server_count) + " servers in Intersight.")   

# Call the network API for Intersight
fi_api_instance = network_api.NetworkApi(api_client)

# Retrieve json formatted data on all fabric interconnects
def get_fi_data():
    global fi_data
    global fi_inventory
    global fi_count
    fi_data = fi_api_instance.get_network_element_summary_list()
    # Handling error scenario if it does not return any entry.
    if not fi_data.results:
        raise NotFoundException(reason="The response does not contain any FI's.")
    #Get the count of FI's
    fi_inventory = fi_data.results
    fi_count = len(fi_inventory)
    print("There are " + str(fi_count) + " fabric interconnects in Intersight.")

get_server_data()
print("-----------------------------------------------------------------")
get_fi_data()

#Write data to export file
with open(export_file_servers, 'w', encoding = 'UTF8', newline = '') as export_data_servers:
    s_writer = csv.writer(export_data_servers, delimiter = ",")
    s_headers = ['name','serial','dn','model','firmware','mgmt_ip_address','management_mode']
    s_writer.writerow(s_headers)
    for server in server_inventory:
        server_name = server['name']
        server_sn = server['serial']
        server_dn = server['dn']
        server_model = server['model']
        server_fw = server['firmware']
        server_ip = server['mgmt_ip_address']
        server_mode = server['management_mode']
        server_data = [server_name, server_sn, server_dn, server_model, server_fw, server_ip, server_mode]
        #NOTE: Writerow takes an interable as an argument, so we need to pass it a list and not a string.
        s_writer.writerow(server_data)
export_data_servers.close()

with open(export_file_fi, 'w', encoding = 'UTF8', newline = '') as export_data_fi:
    f_writer = csv.writer(export_data_fi, delimiter = ",")
    f_headers = ['name','switch_id','serial','dn','model','version','ipv4_address','management_mode']
    f_writer.writerow(f_headers)
    for fi in fi_inventory:
        fi_name = fi['name']
        fi_fabric = fi['switch_id']
        fi_sn = fi['serial']
        fi_dn = fi['dn']
        fi_model = fi['model']
        fi_fw = fi['version']
        fi_ip = fi['ipv4_address']
        fi_mode = fi['management_mode']
        fi_data = [fi_name, fi_fabric, fi_sn, fi_dn, fi_model, fi_fw, fi_ip, fi_mode]
        f_writer.writerow(fi_data)
export_data_fi.close()
