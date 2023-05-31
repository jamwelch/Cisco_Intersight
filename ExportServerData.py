#!/usr/bin/env python
# coding: utf-8
# Tested from a Windows 11 workstation running Python 3.8.12

##############################################
# Modify the api_key and key location
#API KEY
key_id = "KeyGoesHere"
api_secret_file = "F:\Path\To\File.txt"
# Modify the api_key and key location
###############################################

# Import Python modules
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
import math

##################################################
#These file will be created in default location
# Name of export file 
export_file_servers = 'ServerInventory.csv'
export_file_fi = 'FabricInterconnectInventory.csv'
##################################################


# Define function for connecting securely to Intersight
def get_api_client(key_id, api_secret_file, endpoint="https://intersight.com"):
    """
    Function for connecting securely to Intersight.
    Uses the api key and key file above for authorizing access to Intersight.
    Replace the api key and path to the key file above as needed.
    """
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

# Call the network API for Intersight
fi_api_instance = network_api.NetworkApi(api_client)


def make_server_file(file):
    """
    Function to create the file for server data with headers.
    """
    with open(file, 'w', encoding = 'UTF8', newline = '') as f:
        s_writer = csv.writer(f, delimiter = ",")
        s_headers = ['Name','Serial','Dn','Model','Firmware','MgmtIpAddress','ManagementMode','ServiceProfile','OperState','OperPowerState']
        #Write the header row
        s_writer.writerow(s_headers)
    f.close()


def make_fi_file(file):
    """
    Function to create the file for fi data with headers.
    """
    with open(file, 'w', encoding = 'UTF8', newline = '') as f:
        f_writer = csv.writer(f, delimiter = ",")
        f_headers = ['Name','SwitchId','Serial','Dn','Model','Version','OutOfBandIpAddress','ManagementMode','Operability',]
        #Write the header row
        f_writer.writerow(f_headers)
    f.close()


def get_server_count():
    """
    Function for counting the number of servers and determining the number of pages needed.
    The default max is 1000 so if that number is exceeding, 
    then we must use additional pages of json data in oder to collect information on all of the objects.
    """
    global server_data
    global server_page_size
    server_data = api_instance.get_compute_physical_summary_list(count=True)
    i = int(server_data.count)
    # Handling error scenario if it does not return any entry.
    if i < 1:
        raise NotFoundException(reason="The response does not contain any servers.")
    #Print the count of servers
    print("There are " + str(i) + " servers in Intersight.")
    if i < 1000:
        server_page_size = i
    else:
        server_page_size = 1000


def load_server_data(records_per_page):
    """
    Function to load and write the data to the export file for server data.
    """
    global server_inventory
    #Implemented to increase capacity to load data set greater than 1000 records
    #Round up on the number of pages of data to read
    pages = math.ceil(server_data.count/records_per_page)
    print(pages)
    #declare starting values as zero
    x=0 #Number of pages loaded into memory
    y=0 #Number of data rows to skip when loading into memory
    while x < pages: 
        select = "Model,Serial,Name,Dn,MgmtIpAddress,ServiceProfile,Firmware,ManagementMode,OperState,OperPowerState"
        filter = "Serial ne ''" #only return serialized items
        query = api_instance.get_compute_physical_summary_list(top=records_per_page, skip=y, select=select, filter=filter, _preload_content=False)
        server_inventory = json.loads(query.data)['Results']
        x = x+1  #increment page number
        y = y+records_per_page #increment number of skipped records
        # Write data to the file
        write_server_data(export_file_servers)
        #print example data row (the first row of each page) for troubleshooting
        print(len(server_inventory))
        print(server_inventory[0])


# Retrieve json formatted data on all fabric interconnects
def get_fi_count():
    """
    Function for counting the number of fabric interconnects and determining the number of pages needed.
    The default max is 1000 so if that number is exceeding, 
    then we must use additional pages of json data in oder to collect information on all of the objects.
    """
    global fi_data
    global fi_page_size
    fi_data = fi_api_instance.get_network_element_summary_list(count=True)
    i = int(fi_data.count)
    if i < 1:
        raise NotFoundException(reason="The response does not contain any FI's.")
    #Print the count of FI's
    print("There are " + str(i) + " fabric interconnects in Intersight.")
    if i < 1000:
        fi_page_size = i
    else:
        fi_page_size = 1000


def load_fi_data(records_per_page):
    """
    Function to load and write the data to the export file for fi data.
    """
    global fi_inventory
    #Implemented to increase capacity to load data set greater than 1000 records
    #Round up on the number of pages of data to read
    pages = math.ceil(fi_data.count/records_per_page)
    print(pages)
    #declare starting values as zero
    x=0 #Number of pages loaded into memory
    y=0 #Number of data rows to skip when loading into memory
    while x < pages: 
        select = "Model,Serial,Dn,Name,OutOfBandIpAddress,SwitchId,Version,ManagementMode,Operability"
        filter = "Serial ne ''" #only return serialized items
        query = fi_api_instance.get_network_element_summary_list(top=records_per_page, skip=y, select=select, filter=filter, _preload_content=False)
        fi_inventory = json.loads(query.data)['Results']
        x = x+1  #increment page number
        y = y+records_per_page #increment number of skipped records
        #print example data row (the first row of each page) for troubleshooting
        print(fi_inventory[0])
        # Write data to the file
        write_fi_data(export_file_fi)


def write_server_data(file):
    """
    Function to write the server data.
    """
    with open(file, 'a', encoding = 'UTF8', newline = '') as f:
        s_writer = csv.writer(f, delimiter = ",")
        #Declare what will be placed into each column
        for server in server_inventory:
            server_name = server['Name']
            server_serial = server['Serial']
            server_dn = server['Dn']
            server_model = server['Model']
            server_fw = server['Firmware']
            server_mgmt_ip = server['MgmtIpAddress']
            server_mode = server['ManagementMode']
            server_profile = server['ServiceProfile']
            server_state = server['OperState']
            server_power = server['OperPowerState']
            server_data = [server_name, server_serial, server_dn, server_model, server_fw, server_mgmt_ip, server_mode, server_profile, server_state, server_power]
            #NOTE: Writerow takes an interable as an argument, so we need to pass it a list and not a string.
            s_writer.writerow(server_data)
    f.close()


def write_fi_data(file):
    """
    Function to write the fi data.
    """
    with open(file, 'a', encoding = 'UTF8', newline = '') as f:
        f_writer = csv.writer(f, delimiter = ",")
        #Declare what will be placed into each column
        for fi in fi_inventory:
            fi_name = fi['Name']
            fi_fabric = fi['SwitchId']
            fi_serial = fi['Serial']
            fi_dn = fi['Dn']
            fi_model = fi['Model']
            fi_fw = fi['Version']
            fi_ip = fi['OutOfBandIpAddress']
            fi_mode = fi['ManagementMode']
            fi_operability = fi['Operability']
            fi_data = [fi_name, fi_fabric, fi_serial, fi_dn, fi_model, fi_fw, fi_ip, fi_mode, fi_operability]
            #NOTE: Writerow takes an interable as an argument, so we need to pass it a list and not a string.
            f_writer.writerow(fi_data)
    f.close()


# Make the files
make_server_file(export_file_servers)
make_fi_file(export_file_fi)

# Process server data
get_server_count()
print("-----------------------------------------------------------------")
load_server_data(server_page_size)
print("-----------------------------------------------------------------")

# Process fi data
get_fi_count()
print("-----------------------------------------------------------------")
load_fi_data(fi_page_size)
print("-----------------------------------------------------------------")
