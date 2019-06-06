# dds-to-ddl
Convert a DDS file into SQL Table and creates surrogate files.

It won't be 100% all of the time, but should get you 80% of the way there 80% of the time.
This is intended to be a helper, not a flawless converter that you mindlessly run.
Do not use this if you don't know what you're doing.

## Usage
!! DO NOT COMPILE ANY DDS UNTIL YOU HAVE COPIED THE DATA !! 
- Call CVTDDS first
-- This will generate the DDL for your new SQL table.
-- Review the source in QTEMP/QSQLSRC.
-- RUNSQLSTM to create the new table.

- Call CRTDDS next
-- This will generate DDS new versions of your files to point to the new table.
--- The PF will be converted into a LF
--- All existing LFs will be modified 
-- DO NOT COMPILE ANYTHING YET

- Copy your data from the PF into the new table
-- You will need *MAP *DROP

- Now you can compile the DDS

## Limitations
Does not handle multi-format files.
Does not (yet) handle select/omit.
Probably many others...