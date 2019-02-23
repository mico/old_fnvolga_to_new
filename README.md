# Database migration

[![Build Status](https://secure.travis-ci.org/mico/old_fnvolga_to_new.svg)](https://travis-ci.org/mico/old_fnvolga_to_new)
[![Coverage Status](https://img.shields.io/codeclimate/coverage/mico/old_fnvolga_to_new.svg)](https://codeclimate.com/github/mico/old_fnvolga_to_new)
[![Code Climate](https://codeclimate.com/github/mico/old_fnvolga_to_new.svg)](https://codeclimate.com/github/mico/old_fnvolga_to_new)
[![Inline docs](http://inch-ci.org/github/mico/old_fnvolga_to_new.svg)](http://inch-ci.org/github/mico/old_fnvolga_to_new)

Copy data from one database to another and apply changes to it.
Changes could applied to data and to structure.

## Usage

```
./bin/migrate entity_name
```
Where entity name is name of yml migration file without .yml

Changes described in migrations/*.yml files
Example:

```
fields:
  Title: title
custom_fields:
  logo: "#{row_from['Picture'].sub('images/', '')}"
from: Articles
to: fs_newspaper_article
relations:
  Issue:
    type: onetomany
```
