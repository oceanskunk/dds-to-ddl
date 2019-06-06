# dds-to-ddl
Convert a DDS file into SQL Table and creates surrogate files.

It won't be 100% all of the time, but should get you 80% of the way there 80% of the time.
This is intended to be a helper, not a flawless converter that you mindlessly run.
**__Do not use this if you don't know what you're doing.__**

## Usage

1. Clone the repo
    * `git clone https://github.com/oceanskunk/dds-to-ddl.git`

2. Compile the programs
    * `CRTSQLRPGI OBJ(<your library>/CVTDDS) SRCSTMF('/home/<USER>/dds-to-ddl/qrpglesrc/CVTDDS.SQLRPGLE')`
    * `CRTSQLRPGI OBJ(<your library>/CRTDDS) SRCSTMF('/home/<USER>/dds-to-ddl/qrpglesrc/CRTDDS.SQLRPGLE')`

3. Call CVTDDS first
    * This will generate DDL for your new SQL table.
    * Review the source in QTEMP/QSQLSRC.
    * RUNSQLSTM to create the new table.

4. Call CRTDDS next
    * This will generate DDS for new versions of the existing files.
    * The PF will be converted into a LF.
    * All existing LFs will be based on the new SQL table.
    * Review all the source in QTEMP/QSQLSRC (yes, the DDS is in QSQLSRC).

**__DO NOT COMPILE ANYTHING YET__**

5. Copy your data from the PF into the new table
    * You will need *MAP *DROP

6. Now you can compile the DDS

## Limitations
* Does not handle multi-format files.
* Does not (yet) handle select/omit.
* Probably many others...
