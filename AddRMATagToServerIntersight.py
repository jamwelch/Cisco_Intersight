"""
Author: James Welch
Contact: jamwelch@cisco.com
Summary: The Cisco Intersight Universal API Calls module provides
          a set of functions that simplify creation, retrieval,
          modification, and deletion of resources on Cisco Intersight.
          
          This script will add, remove, and change the RMA tags for server objects in intersight.
          Using the RMA tags on server objects in Intersight is NOT yes supported by Cisco, 
          so do not use this script unless explicitly prescribed by a Cisco engineer.
          
          The script assumes you have a csv formatted file containing 2 columns.
          Find the file "example.csv" in this repository.
          The file should be formatted in this fashion:
          
          serial_number,rma_email
          SERIAl1,name@domain.com
          SERIAL1,name@domain.com

          Use the same headings as above in your data file.
          Make sure the serial numbers match the server object you intend to tag 
          with the specific e-mail address. 
          
          This script currently does not support using multiple e-mail addresses for an RMA Tag.
        
"""

# Copy intersight_universal_api_calls.py to local path and ensure it is in path (see print output to verify)
# https://github.com/ugo-emekauwa/intersight-universal-api-calls.git

# Modify the api_key and key location in the intersight_universal_api_calls.py script

# Import needed Python modules
import sys
import json
import requests
import csv
import os
import intersight
from intersight.intersight_api_client import IntersightApiClient

# Imports required modules from Intersight Universal API Calls (assumes the file is local and contains api key and secret key location.)
from intersight_universal_api_calls import iu_get
from intersight_universal_api_calls import iu_get_moid
from intersight_universal_api_calls import iu_patch_moid

# Variables for use in the script.
#
# Update the input_file variable with the name of the file to read. Ensure it is in the same file folder as a the script.
input_file = 'rma_email_list.csv'

# Define API endpoints for reading data in Intersight.
all_blades = "compute/Blades"
all_rack_units = "compute/RackUnits"

# Functions to be used in the script
#
# Retrieve json data on all servers
def get_server_data():
    blades = iu_get(all_blades)
    rack_units = iu_get(all_rack_units)
    # Create a list of dictionaries from the json data
    blade_list = blades['Results']
    rack_list = rack_units['Results']
    global all_servers
    all_servers = blade_list + rack_list

# Loop through all of the servers to find ones listed in the file    
def identify_server(sn):
    for server in all_servers:
        print("Searching for a server using identify server function")
        if sn == server['Serial']:
            global old_tags
            global moid
            moid = server['Moid']
            global dn
            dn = server['Dn']
            old_tags = server['Tags']
            global hw
            if "blade" in dn:
                hw = "compute/Blades"
            if "rack" in dn:
                hw = "compute/RackUnits"

# Add a tag to a server object                
def add_tags(email):
    print("Running add tags function")
    # Add rma tag dictionary to a new list of dictionaries
    new_tags_list = [rmatag]
    # Loop through any existing tags and append them to the newly created list
    for old_tag_dict in old_tags:
        new_tags_list.append(old_tag_dict)
    # Use the list of dictionaries to create the json formatted Tags object to replace the existing Tags code for each server
    new_tags = {'Tags': new_tags_list}
    print ("Proceeding with Update for " + sn + " at " + dn)
    try:
        # Universal command to patch Intersight objects. This is where the magic happens!
        # Pass the variables obtained from the identify_server function along with the new Tags JSON code
        iu_patch_moid(hw,moid,new_tags)
        print("Check API to verify that the tags are correct. https://intersight.com/apidocs/apirefs/api/v1/compute/Blades/get/#")
    except:
        print("Error")

# Determine if the existing tags need to be updated       
def compare_tags(email):
    # Create a dictionary for the rma tag
    global rmatag
    rmatag = dict()
    rmatag = {"Key": "AutoRMAEmail","Value": email}
    print("Running compare tags function.")
    for tag in old_tags:
        if tag["Key"] == "AutoRMAEmail":
            print("Found tag for " + sn + " at " + dn)
            print(tag)
            if tag['Value'] == rmatag['Value']:
                print("This tag already exists for " + sn + " at " + dn)
                break
            elif tag['Value'] != rmatag['Value']:
                print("This tag has changed, updating tag for " + sn + " at " + dn)
                replace_tags(email)
            else:
                print("Error: Something went wrong.")
        else:
            print("Tag not detected for " + sn + " at " + dn)
            add_tags(email)

# Replace the RMA tag if the e-mail address has changed            
def replace_tags(email):
    print("Running replace tags function")
    for tg in old_tags:
        if tg['Key'] == rmatag['Key']:
            old_tags.remove(tg)
            print("RMA tag removed for " + sn + " at " + dn)
            add_tags(email)
            
    
# Run the script
#
# Open data file and read each line performing update function for each line
get_server_data()
with open(input_file, 'r') as csvfile:
    for line in csv.DictReader(csvfile):
        email = line['rma_email']
        sn = line['serial_number']
        identify_server(sn)
        compare_tags(email)
