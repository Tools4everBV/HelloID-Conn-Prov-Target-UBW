# HelloID-Conn-Prov-Target-UBW

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Target-UBW](#helloid-conn-prov-target-UBW)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
    - [Correlation configuration](#correlation-configuration)
    - [Supported features](#supported-features)
    - [Field mapping](#field-mapping)
  - [Remarks](#remarks)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Target-UBW_ is a _target_ connector. _UBW_ provides a set of REST API's that allow you to programmatically interact with its data.

## Getting started

### Prerequisites

### Connection settings

The following settings are required to connect to the API.

| Setting      | Description                             | Mandatory |
| ------------ | --------------------------------------- | --------- |
| UserName     | The UserName to connect to the API      | Yes       |
| Password     | The Password to connect to the API      | Yes       |
| BaseUrl      | The URL to the API                      | Yes       |
| DefaultRoles | Default roleId for every account        | Yes       |
| CompanyId    | Company Id for mananging relevant roles | Yes       |

### Correlation configuration

The correlation configuration is used to specify which properties will be used to match an existing account within _UBW_ to a person in _HelloID_.

| Setting                   | Value                             |
| ------------------------- | --------------------------------- |
| Enable correlation        | `True`                            |
| Person correlation field  | `PersonContext.Person.ExternalId` |
| Account correlation field | `PersonId`                        |

> [!TIP]
> _For more information on correlation, please refer to our correlation [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems/correlation.html) pages_.

> [!IMPORTANT]
> If the Person correlation field value is not corresponding to any field in the UBW target accounts, it may be necessary to add a custom field on the person to correctly implement reconciliation.

### Supported features

The following features are available:

| Feature                                   | Supported | Actions                                 | Remarks |
| ----------------------------------------- | --------- | --------------------------------------- | ------- |
| **Account Lifecycle**                     | ✅        | Create, Update, Enable, Disable, Delete |         |
| **Permissions**                           | ✅        | Retrieve, Grant, Revoke                 | Static  |
| **Resources**                             | ❌        | -                                       |         |
| **Entitlement Import: Accounts**          | ✅        | -                                       |         |
| **Entitlement Import: Permissions**       | ✅        | -                                       |         |
| **Governance Reconciliation Resolutions** | ✅        | -                                       |         |

### Field mapping

The field mapping can be imported by using the _fieldMapping.json_ file.

## Remarks

### Static value's and order

Both the **create** and **update** files contain the account mapping. The property's are ordered because UBW doesn't accept the object if the value's if the order is different.

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
- roleStatus

Make sure to verify the value of the property's listed above with the customer.

For setting the defaultLogonCompany at least one role is mandatory with a rolestatus. In the configuration one or more roles can be defined to add during creation of an account.

### User accounts

This connector only creates user accounts. During creation we validate the exsistence of the employee account and user account.
Both objects contain a property called _[personId]_.

The flow is as follows:

- Lookup the employee by _[personId]_. We assume the _[personId]_ is the _[ExternalId]_ for a HelloID person.
  - If no employee account is found, we cannot continue and the process will exit.
  - If an employee account has been found:
    - Retrieve all user accounts. (User accounts do have the property _[personId]_ but we cannot get it directly).
    - Verify if there is a user account that matches with the _[personId]_ in the account mapping.
      - When a user account has been found:
        - Correlate the account
      - When a user account cannot be found:
        - Create the user account and connect the user account with the employee account.
      - When multiple user accounts have been found:
        - DomainUser is removed from the update to prevent single sign on and let the user choose between the available accounts during login

## Development resources

### API endpoints

The following endpoints are used by the connector

| Endpoint   | Description                                                             |
| ---------- | ----------------------------------------------------------------------- |
| /Users     | This endpoint is used to create, update, enable, disable, delete users. |
| /Employees | This endpoint is used to verify if a user has a linked employee account |
| /Roles     | This endpoint is used to retrieve role permissions.                     |

### API documentation

> [!TIP]
> _API documentation is only available through the on-premise system_.

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/target-systems/powershell-v2-target-systems.html) pages_.

> [!TIP]
> _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
