"""
Author: James Welch
Contact: jamwelch@cisco.com
Summary:  This script will add and change the RMA tags for server objects in intersight.
          Using the RMA tags on server objects in Intersight is NOT yes supported by Cisco, 
          so do not use this script unless explicitly prescribed by a Cisco engineer.
          
          The script does not delete any tags including pre-existing server tags or RMA tags not listed in the csv file.
          
          The script assumes you have a csv formatted file containing 2 columns.
          Find the file "example.csv" in this repository.
          The file should be formatted in this fashion:
          
          serial_number,rma_email
          SERIAl1,name@domain.com
          SERIAL1,name@domain.com

          Use the same headings as above in your data file.
          Make sure the serial numbers match the server object you intend to tag 
          with a specific e-mail address. 
                    
        
"""

# Modify the api_key and key location below
key_id = "replace with your key id"
api_secret_file = "c:\replace\with\your\path\to\secretkey.txt"

# Import needed Python modules
import sys
import json
import re
import csv
import os
import intersight
from intersight.api import compute_api

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

          

# Update the input_file variable with the name of the file to read. Ensure it is in the same location as the script.
# File should had 2 headings in top line "serial_number" & "rma_email".
# File should use ";" and NOT "," as the delimiter.  This enables the functionality of tagging with mulitiple e-mail addresses separated by a comma.
# Do not use quotes around the elements in the file.
# Example.csv
# serial_number;rma_email
# S3R1ALNU1;personA@company.com,personB@company.com

input_file = 'input_file.csv'

# Connect to Intersight as an API client
api_client = get_api_client(key_id, api_secret_file)

# Call the compute API for Intersight
api_instance = compute_api.ComputeApi(api_client)

# Retrieve json formatted data on all servers
def get_server_data():
    blade_data = api_instance.get_compute_blade_list()
    rack_data = api_instance.get_compute_rack_unit_list()
    blade_list = blade_data['results']
    rack_list = rack_data['results']
    global all_servers
    all_servers = [blade_list + rack_list]
          
# Loop through the list of all servers to find the ones listed in the file 
def identify_server(sn):
    for s_list in all_servers:
        print("Searching for a server using identify server function")
        #print(server)
        for server in s_list:
            if sn == server['serial']:
                global old_tags
                global moid
                moid = server['moid']
                global dn
                dn = server['dn']
                old_tags = server['tags']
                print(old_tags)
                global hw
                if "blade" in dn:
                    hw = "blade"
                if "rack" in dn:
                    hw = "rack_unit"
                    
# Determine if the existing tags need to be updated  
def compare_tags(email):
    # Create a dictionary for the rma tag
    global rmatag
    rmatag = dict()
    rmatag = {"key": "AutoRMAEmail","value": email}
    print("Running compare tags function.")
    for tag in old_tags:
        if tag["key"] == "AutoRMAEmail":
            print("Found tag for " + sn + " at " + dn)
            print(tag)
            if tag['value'] == rmatag['value']:
                print("This tag already exists for " + sn + " at " + dn)
                break
            elif tag['value'] != rmatag['value']:
                print("This tag has changed, updating tag for " + sn + " at " + dn)
                replace_tags(email)
            else:
                print("Error: Something went wrong.")
        else:
            print("Tag not detected for " + sn + " at " + dn)
            add_tags(email)
          
# Add a tag to a server object                
def add_tags(email):
    print("Running add tags function")
    # Add rma tag dictionary to a new list of dictionaries
    new_tags_list = [rmatag]
    # Loop through any existing tags and append them to the newly created list
    for old_tag_dict in old_tags:
        new_tags_list.append(old_tag_dict)
    # Use the list of dictionaries to create the json formatted Tags object to replace the existing Tags code for each server
    new_tags = {'tags': new_tags_list}
    print ("Proceeding with Update for " + sn + " at " + dn)         
    try:
        if hw == "blade":
            api_instance.update_compute_blade(moid, new_tags)
        if hw == "rack_unit":
            api_instance.update_compute_rack_unit(moid, new_tags)
        print("Check API to verify that the tags are correct. https://intersight.com/apidocs/apirefs/api/v1/compute/Blades/get/#")
    except:
        print("Error")

# Replace the RMA tag if the e-mail address has changed            
def replace_tags(email):
    print("Running replace tags function")
    for tg in old_tags:
        if tg['key'] == rmatag['key']:
            old_tags.remove(tg)
            print("RMA tag removed for " + sn + " at " + dn)
            add_tags(email)
                    
# Run the script
#
# Open data file and read each line performing update function for each line
get_server_data()
with open(input_file, 'r') as csvfile:
    for line in csv.DictReader(csvfile, delimiter = ';'):
        email = line['rma_email']
        sn = line['serial_number']
        identify_server(sn)
        compare_tags(email)
          
# The script will print logging information to help with debugging using a print function from each step of the script.      
