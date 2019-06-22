**free

 // This program will create DDS to convert a PF into a LF.
 //
 // It requires 3 input parms:
 //  1) The library where the existing PF is located
 //  2) The name of the existing PF
 //  3) The name for the new SQL table
 //
 //
 //
 // The DDL for your new table will be in QTEMP/QSQLSRC.
 // There will be comments in there, which are the original
 // lines from the IBM-supplied conversion (which should
 // still be in QTEMP/Q_GENSQL).


 ctl-opt  dftactgrp(*no);
 ctl-opt  debug;
 ctl-opt  option(*srcstmt : *nodebugio : *nounref);
 

 dcl-pi  EntryPlist   extpgm('CRTDDS');
     inLib char(10) const;
     inFile char(10) const;
     inNewFile char(10) const;
 end-pi;


 dcl-pr RunCommand  int(10)   extproc('system');
         *n         pointer   value  options(*string);
 end-pr;
 dcl-s  command  varchar(2046);

 dcl-ds dds    qualified;
     *n        char(1)  pos(6) inz('A');
     nameType  char(1)  pos(17);
     fieldName char(10) pos(19);
     keyword   char(30) pos(45);
 end-ds;

 Exec SQL Set Option CLOSQLCSR=*ENDMOD, COMMIT=*NONE, DATFMT=*ISO;

 command = 'CRTSRCPF FILE(QTEMP/QSQLSRC) RCDLEN(200) MBR(*NONE)';
 RunCommand(command);

 GenerateNewFile(inLib : inFile : 'PF');
 CreateLogicalFiles(inLib : inFile);

 *inlr = *on;
 return;



 //----------------------------------------------------------------------------------------
 // Create New Logical Files
 // Find all related LFs and create new source for them.
 //----------------------------------------------------------------------------------------
 dcl-proc  CreateLogicalFiles;
     dcl-pi  CreateLogicalFiles;
         inLib  char(10) const;
         inFile char(10) const;
     end-pi;

     dcl-ds  logicalFiles  qualified  dim(100);
         lib  char(10);
         file char(10);
     end-ds;
     dcl-s  rowsFetched  int(10);
     dcl-s  i  int(10);
     dcl-s  endOfData  ind;

     // List all the dependent files (this list will include SQL Views)
     command = 'DSPDBR FILE(' + %trim(inLib) + '/' + %trim(inFile) + ') +
                       OUTPUT(*OUTFILE) OUTFILE(QTEMP/DSPDBR)';
     RunCommand( command );

     // Get a list of the dependent LFs (exlcuding SQL Views)
     Exec SQL
      DECLARE dds2ddl_lf_cursor CURSOR FOR
        SELECT system_table_schema
             , system_table_name
        FROM qtemp/dspdbr
        INNER JOIN qsys2/systables
          ON whrefi = system_table_name
         AND whreli = system_table_schema
         AND table_type = 'L';

     Exec SQL
      OPEN dds2ddl_lf_cursor;

     dou endOfData;

         Exec SQL
           FETCH dds2ddl_lf_cursor
           FOR 100 ROWS
           INTO :logicalFiles;

         rowsFetched = sqler3;
         endOfData = (sqler5 = 100);

         for i = 1 to rowsFetched;
             GenerateNewFile( logicalFiles(i).lib
                            : logicalFiles(i).file
                            : 'LF'
                            );
         endfor;
     enddo;

     Exec SQL
      CLOSE dds2ddl_lf_cursor;

     return;

 end-proc  CreateLogicalFiles;




 //----------------------------------------------------------------------------------------
 // Generate New File
 // Creates a new source member for the original PF.
 // The PF will become a LF pointing to the new SQL table.
 //----------------------------------------------------------------------------------------
 dcl-proc  GenerateNewFile;
     dcl-pi  *n;
         inLib char(10) const;
         inFile char(10) const;
         inType  char(2) const;
     end-pi;

     dcl-s rcdfmt  char(10);
     dcl-s unique  char(1);
     dcl-s keys    int(10);

     CreateSourceMember(inFile);

     command = 'DSPFD FILE(' + %trim(inLib) + '/' + %trim(inFile) + ') +
                      TYPE(*RCDFMT) +
                      OUTPUT(*OUTFILE) +
                      FILEATR(*' + inType + ') +
                      OUTFILE(QTEMP/RECORDFMT)';
     RunCommand( command );
     Exec SQL
       SELECT rfname
       INTO :rcdfmt
       FROM qtemp/recordfmt;


     command = 'DSPFD FILE(' + %trim(inLib) + '/' + %trim(inFile) + ') +
                      TYPE(*ACCPTH) +
                      OUTPUT(*OUTFILE) +
                      FILEATR(*' + inType + ') +
                      OUTFILE(QTEMP/KEYLIST)';
     RunCommand( command );
     Exec SQL
       SELECT DISTINCT apuniq , apnkyf
       INTO :unique , :keys
       FROM qtemp/keylist;

     if unique = 'Y';
         dds.nameType = *blanks;
         dds.fieldName = *blanks;
         dds.keyword = 'UNIQUE';
         WriteSource(dds);
     endif;

     dds.nameType = 'R';
     dds.fieldName = rcdfmt;
     dds.keyword = 'PFILE(' + %trim(inNewFile) + ')';
     WriteSource(dds);

     AddColumns(inLib : inFile);
     if keys > 0;
         AddKeyFields(inLib : inFile);
     endif;

     return;

 end-proc  GenerateNewFile;


 //----------------------------------------------------------------------------------------
 // Add Columns
 // Adds all the existing columns to the new logical file
 //----------------------------------------------------------------------------------------
 dcl-proc  AddColumns;
     dcl-pi  AddColumns;
         inLib  char(10) const;
         inFile char(10) const;
     end-pi;

     dcl-s rowsFetched  int(10);
     dcl-s i  int(10);
     dcl-s endOfData  ind;
     dcl-ds column    qualified dim(100) inz;
         system_name  char(10);
     end-ds;

     Exec SQL
      DECLARE dds2ddl2_column_cursor CURSOR FOR
      SELECT system_column_name
      FROM qsys2.syscolumns2
      WHERE system_table_schema = :inLib
        AND system_table_name = :inFile
      ORDER BY ordinal_position;

     Exec SQL
      OPEN dds2ddl2_column_cursor;

     dou EndOfData;

         Exec SQL
          FETCH dds2ddl2_column_cursor
          FOR 100 ROWS
          INTO :column;

         rowsFetched = sqler3;
         endOfData = (sqler5 = 100);

         for i = 1 to rowsFetched;
             dds.nameType = *blanks;
             dds.fieldName = column(i).system_name;
             dds.keyword = *blanks;
             WriteSource(dds);
         endfor;

     enddo;

     Exec SQL
      CLOSE dds2ddl2_column_cursor;

     return;

 end-proc  AddColumns;



 //----------------------------------------------------------------------------------------
 // Add Key Fields
 // Add the key columns to the source (they are listed in QTEMP/KEYLIST).
 //----------------------------------------------------------------------------------------
 dcl-proc  AddKeyFields;
     dcl-pi  AddKeyFields;
         inLib  char(10) const;
         inFile char(10) const;
     end-pi;

     dcl-s rowsFetched  int(10);
     dcl-s i  int(10);
     dcl-s endOfData  ind;
     dcl-ds column    qualified dim(100) inz;
         system_name  char(10);
     end-ds;

     Exec SQL
      DECLARE dds2ddl2_key_cursor CURSOR FOR
      SELECT apkeyf
      FROM qtemp/keylist
      ORDER BY apkeyn;

     Exec SQL
      OPEN dds2ddl2_key_cursor;

     dou EndOfData;

         Exec SQL
          FETCH dds2ddl2_key_cursor
          FOR 100 ROWS
          INTO :column;

         rowsFetched = sqler3;
         endOfData = (sqler5 = 100);

         for i = 1 to rowsFetched;
             dds.nameType = 'K';
             dds.fieldName = column(i).system_name;
             dds.keyword = *blanks;
             WriteSource(dds);
         endfor;

     enddo;

     Exec SQL
      CLOSE dds2ddl2_key_cursor;

     return;

 end-proc  AddKeyFields;


 //----------------------------------------------------------------------------------------
 // Create Source Member
 // Adds a member to QTEMP/QSQLSRC
 //----------------------------------------------------------------------------------------
 dcl-proc  CreateSourceMember;
     dcl-pi  CreateSourceMember;
         inFile  char(10) const;
     end-pi;

   dcl-s  command  varchar(2056);

   command = 'ADDPFM FILE(QTEMP/QSQLSRC) MBR(' + %trim(inFile) + ') +
                     TEXT(''DDS to DDL conversion'') +
                     SRCTYPE(LF)';
   RunCommand(command);

   command = 'CREATE OR REPLACE ALIAS qtemp/dds_source +
              FOR QTEMP/QSQLSRC (' + %trim(inFile) + ')';

   Exec SQL
    EXECUTE IMMEDIATE :command;

   Exec SQL
    DELETE FROM qtemp/dds_source
    WHERE 1=1;

   return;

 end-proc  CreateSourceMember;


 //----------------------------------------------------------------------------------------
 // Write Source
 // Writes to the new DDL source member
 //----------------------------------------------------------------------------------------
 dcl-proc  WriteSource;
   dcl-pi  WriteSource;
       inSource  char(80) const;
   end-pi;

   Exec SQL
    INSERT INTO qtemp.dds_source
    (SRCDTA)
    VALUES
    (:inSource);

   return;

 end-proc  WriteSource;


 //----------------------------------------------------------------------------------------
 // Signal Error
 // Send an error message and end the process
 //----------------------------------------------------------------------------------------
 dcl-proc  SignalError;
     dcl-pi *n;
         inError  varchar(79) const;
     end-pi;

     dcl-pr Exit    extproc('system');
         *n         uns(3) value;
     end-pr;
     dcl-s  dsplyError char(50);

     dsplyError = inError;
     DSPLY dsplyError '';

     // Is there any clean-up that we need to do here???

     // Exit the program immediately
     Exit(0);

 end-proc  SignalError;

