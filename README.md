# HelloID-Conn-Prov-Target-UBW

> This connector is not tested with a HelloID environment. Changes might to have to be made to the code according to your environment.

<p align="center">
  <img src="https://www.unit4.com/sites/default/files/images/logo.svg">
</p>

## Table of contents

- [Introduction](#Introduction)
- [Getting started](#Getting-started)
  + [Connection settings](#Connection-settings)
  + [Prerequisites](#Prerequisites)
  + [Remarks](#Remarks)
- [Setup the connector](@Setup-The-Connector)
- [Getting help](#Getting-help)
- [HelloID Docs](#HelloID-docs)

## Introduction

_HelloID-Conn-Prov-Target-UBW_ is a _target_ connector. Unit4 Business World provides a set of REST API's that allow you to programmatically interact with it's data. The HelloID connector uses the API endpoints listed in the table below.

> Unit4 Business World is a on-premises application.

| Endpoint     | Description |
| ------------ | ----------- |
| /Users       | This endpoint is used to create,update,delete users. |
| /Employees   | This endpoint is used to verify if a user has a linked employee account |

## Getting started

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                        | Mandatory   |
| ------------ | -----------                        | ----------- |
| UserName     | The UserName to connect to the Business World API | Yes         |
| Password     | -                                  | Yes         |
| BaseUrl      | The URL to the API                 | Yes         |

### Remarks

#### Static value's and order

Both the __create__ and __update__ files contain the account mapping. The property's are ordered because UBW doesn't accept the object if the value's if the order is different. 

The account mapping also contains a few property's which are static value's. These property's are:

General:
- alertMedia
- defaultLogonCompany
- languageCode
- printer

userStatus
- status

roleAndCompany:
- companyId
- roleId

Make sure to verify the value of the property's listed above with the customer.

#### User accounts

This connector only creates user accounts. During creation we validate the exsistence of the employee account and user account.
Both objects contain a property called _[personId]_.

The flow is as follows:

-  Lookup the employee by _[personId]_. We assume the _[personId]_ is the _[ExternalId]_ for a HelloID person.
    - If no employee account is found, we cannot continue and the process will exit.
    - If an employee account has been found:
      - Retrieve all user accounts. (User accounts do have the property _[personId]_ but we cannot get it directly).
      - Verify if there is a user account that matches with the _[personId]_ in the account mapping.
        - When a user account has been found:
          - Correlate the account
        - When a user account aannot be found:
          - Create the user account and connect the user account with the employee account.

#### Update

At this point the update.ps1 only updates the description as an example. Most (if not all) property's within Unit4 Business World are static value's.
The user object itself does not contain any user information apart from the _[userId]_ and _[userName]_

## Setup the connector

> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/hc/en-us/articles/360012558020-Configure-a-custom-PowerShell-target-system) pages_

## Getting help

> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
