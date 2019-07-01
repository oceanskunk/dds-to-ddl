**free

 // This program will convert a physical file (PF) into an SQL table.
 // More specifically, it will generate the DDL so that *YOU* can do
 // the conversion.
 //
 // It requires 3 input parms:
 //  1) The library where the existing PF is located
 //  2) The name of the existing PF
 //  3) The name for the new SQL table
 //
 // It will use the IBM procedure to generate the DDL, and then
 // modifies it to provide a long name for the table, an identity
 // column, alias for each of the fields (columns), and some
 // metadata columns.
 //
 // The DDL for your new table will be in QTEMP/QSQLSRC.
 // There will be comments in there, which are the original
 // lines from the IBM-supplied conversion (which should
 // still be in QTEMP/Q_GENSQL).


 ctl-opt  dftactgrp(*no);
 ctl-opt  debug;
 ctl-opt  option(*srcstmt : *nodebugio : *nounref);


 dcl-pi  EntryPlist   extpgm('CVTDDS');
     inLib char(10) const;
     inFile char(10) const;
     inNewFile  char(10) const;
 end-pi;

 Exec SQL Set Option CLOSQLCSR=*ENDMOD, COMMIT=*NONE, DATFMT=*ISO;

 CreateSourceMembers();
 GenerateSql();
 GenerateNewMember();

 *inlr = *on;
 return;


 //----------------------------------------------------------------------------------------
 // Generate New Member
 // Reads the generated SQL and formats it nicely into a new member in QTEMP/QSQLSRC.
 //----------------------------------------------------------------------------------------
 dcl-proc  GenerateNewMember;

   dcl-ds  ddl  qualified  dim(500);
       seq  zoned(6);
       dat  zoned(6);
       src  char(188);
   end-ds;
   dcl-s  rowsFetched  int(10);
   dcl-s  i  int(10);
   dcl-s  endOfData  ind;


   AssociateResultSet();

   dou endOfData;

       Exec SQL
         FETCH generated_source
         FOR 500 ROWS
         INTO :ddl;

       rowsFetched = sqler3;
       endOfData = (sqler5 = 100);

       for i = 1 to rowsFetched;
           FormatLine(ddl(i).src);
       endfor;

   enddo;

   Exec SQL
     CLOSE generated_source;

   return;

 end-proc  GenerateNewMember;



 //----------------------------------------------------------------------------------------
 // Format Line
 // Reads a single line from the generated DDL and writes to the new source member.
 //----------------------------------------------------------------------------------------
 dcl-proc  FormatLine;
     dcl-pi *n;
         inSource  char(188) const;
     end-pi;

     dcl-s  currentStep char(2)  static;
     dcl-s  scratchPad  char(188);
     dcl-s  columnName  char(11);
     dcl-c  START_COLUMN_DEFINITIONS  '(';
     dcl-c  END_COLUMN_DEFINITIONS  ')';
     dcl-c  DEFINE_COLUMNS  'DC';
     dcl-c  LABEL_TABLE  'LT';
     dcl-c  LABEL_COLUMN  'LC';
     dcl-c  BLANK_LINE  ' ';

     // Keep comments and blank lines
     if inSource = *blanks
     or StartsWith(%trim(inSource) : '-- ');
         WriteSource(inSource);
         if inSource = *blanks;
             clear currentStep;
         endif;

     // Create table clause
     elseif StartsWith(%trim(inSource) : 'CREATE TABLE ');
         WriteSource('-- ' + inSource);
         CreateTableClause();

         WriteSource(START_COLUMN_DEFINITIONS);
         currentStep = DEFINE_COLUMNS;

     // Column definition
     elseif currentStep = DEFINE_COLUMNS;
         // If a PF is defined with UNIQUE key(s), the generated source
         // will include a PRIMARY KEY that we don't want to include.
         if not StartsWith(%trim(inSource) : 'PRIMARY KEY');
             WriteSource(BLANK_LINE);
             CreateColumn(inSource);
         endif;

         // If the last character is an end-parenthesis, we're finished
         // with defining the columns.
         if EndsWith(%trim(inSource) : ')');
             AddMetadataColumns();
             WriteSource(END_COLUMN_DEFINITIONS);
         endif;

     // Record Format definition
     elseif StartsWith(%trim(inSource) : 'RCDFMT ');
         WriteSource(inSource);

     // Label on table
     elseif StartsWith(%trim(inSource) : 'LABEL ON TABLE ')
     or currentStep = LABEL_TABLE;
         if currentStep <> LABEL_TABLE;
             // Remove the hard-coded library name
             // and use the new system name
             scratchPad = %scanrpl( %trim(inLib) + '.' + %trim(inFile)
                                  : %trim(inNewFile)
                                  : inSource );
             WriteSource(scratchPad);
             currentStep = LABEL_TABLE;
         else;
             WriteSource(inSource);
         endif;
         if EndsWith(%trim(inSource) : ';');
             clear currentStep;
         endif;

     // Label on column
     elseif StartsWith(%trim(inSource) : 'LABEL ON COLUMN ')
     or currentStep = LABEL_COLUMN;
         if currentStep <> LABEL_COLUMN;
             // Remove the hard-coded library name
             // and use the new system name
             scratchPad = %scanrpl( %trim(inLib) + '.' + %trim(inFile)
                                  : %trim(inNewFile)
                                  : inSource );
             WriteSource(scratchPad);
             WriteSource('(');
             currentStep = LABEL_COLUMN;
         else;
             columnName = %subst(inSource : 3 : %scan(' ' : inSource : 3) - 3);
             columnName = %scanrpl('"' : '' : columnName);
             scratchPad = %subst(inSource : %scan(' ' : inSource : 3) );
             if EndsWith(%trim(scratchPad) : ',');
                  scratchPad = %subst(scratchPad : 1 : %len(%trim(scratchPad)) - 1);
             endif;
             if StartsWith(%trim(inSource) : '(');
                 scratchPad = '  ' + columnName + %trim(scratchPad);
             else;
                 scratchPad = ', ' + columnName + %trim(scratchPad);
             endif;
             WriteSource(scratchPad);
         endif;
         if EndsWith( %trim(inSource) : ';');
             clear currentStep;
         endif;

     // Include everything else
     else;
         scratchPad = %scanrpl(%trim(inLib) + '.' + %trim(inFile)
                              : %trim(inNewFile)
                              : inSource
                              );
         WriteSource(scratchPad);

     endif;

     return;

 end-proc  FormatLine;



 //----------------------------------------------------------------------------------------
 // Create Column
 // Adds a column defintion to the new DDL source
 //----------------------------------------------------------------------------------------
 dcl-proc  CreateColumn;
     dcl-pi  CreateColumn;
         inSource  char(188) const;
     end-pi;

     dcl-s  systemName  char(10);
     dcl-s  sqlName     varchar(128);
     dcl-s  columnText   char(50);
     dcl-s  columnType   varchar(10);
     dcl-s  columnLength int(10);
     dcl-s  columnCcsid  int(10);
     dcl-s  columnScale  int(10);
     dcl-s  columnAllowNull  ind;
     dcl-s  columnHasDefault  ind;
     dcl-s  columnDefaultValue  varchar(128);
     dcl-s  isFirstColumn  ind;

     dcl-s  column char(36);
     dcl-s  defn  char(35);
     dcl-s  ccsid  varchar(15);
     dcl-s  allocate varchar(20);
     dcl-s  scanPos1  int(10);
     dcl-s  scanPos2  int(10);
     dcl-s  comma   char(3)  inz(',  ');
     dcl-s  nullable  char(10);
     dcl-s  dftValue  varchar(150);
     dcl-s  SMALL_TAB   char(5);
     dcl-s  BIG_TAB   char(40);
     dcl-c  BLANK_LINE  ' ';

     systemName = %subst( %trim(%scanrpl('"' : '' : inSource))
                        : 1
                        : %scan(' ' : %trim(%scanrpl('"' : '' : inSource)))
                        );


     Exec SQL
       SELECT CASE WHEN ordinal_position = 1 THEN '1' ELSE '0' END AS isFirstColumn
            , column_name  AS sqlName
            , COALESCE(CAST(column_text AS CHAR(50) CCSID 37), '')
            , data_type
            , length
            , COALESCE(ccsid, -1)
            , COALESCE(scale, -1)
            , CASE WHEN is_nullable = 'Y' THEN '1' ELSE '0' END as allowNull
            , CASE WHEN has_default = 'Y' THEN '1' ELSE '0' END as hasDefault
            , COALESCE(CAST(column_default AS CHAR(128) CCSID 37), '')
       INTO :isFirstColumn
          , :sqlName
          , :columnText
          , :columnType
          , :columnLength
          , :columnCcsid
          , :columnScale
          , :columnAllowNull
          , :columnHasDefault
          , :columnDefaultValue
       FROM qsys2.syscolumns2
       WHERE system_table_schema = :inLib
         AND system_table_name = :inFile
         AND system_column_name = :systemName;


     if isFirstColumn;
         AddIdentityColumn();
         WriteSource(BLANK_LINE);
     endif;

     WriteSource('-- ' + inSource);

     if sqlName = systemName;
         if columnText <> *blanks;
             column = %trim(columnText);
         else;
             column = %trim(sqlName) + '_SQL_NAME';
         endif;
     else;
         column = sqlName;
     endif;

     // convert special characters to words and underscores
     Exec SQL
       SET :column = TRIM(REPLACE(:column , '%' , 'Pct'));

     Exec SQL
       SET :column = REGEXP_REPLACE( TRIM(:column)
                                   , '[^A-Za-z0-9]'
                                   , '_'
                                   );

     Exec SQL
       SET :column = REPLACE(:column , '__' , '_');


     defn = FormatFieldDefinition( columnType
                                 : columnLength
                                 : columnScale
                                 );

     if columnType = 'VARCHAR'
     and %scan( ' ALLOCATE(' : inSource) > 0;
         scanPos1 = %scan( 'ALLOCATE(' : inSource);
         scanPos2 = %scan( ')' : inSource : scanPos1);
         scanPos1 += 9;
         allocate = 'ALLOCATE(' + %subst(inSource : scanPos1 : scanPos2 - scanPos1 + 1);
     endif;

     if columnCcsid >= 0
     and columnType <> 'DATE'
     and columnType <> 'TIME'
     and columnType <> 'TIMESTMP';
         ccsid = 'CCSID ' + %char(columnCcsid);
         if allocate <> *blanks;
             ccsid = ' ' + ccsid;
         endif;
     endif;

     if not columnAllowNull;
         nullable = 'NOT NULL';
     endif;

     if columnHasDefault;
         dftValue = 'WITH DEFAULT ' + columnDefaultValue;
     endif;

     WriteSource( comma + column + ' FOR COLUMN ' + systemName );
     WriteSource( SMALL_TAB + defn + allocate + ccsid );
     WriteSource( BIG_TAB + nullable );
     WriteSource( BIG_TAB + dftValue );


 end-proc  CreateColumn;


 //----------------------------------------------------------------------------------------
 // Format Field Definition
 // Formats the field definintion based on type, length, and scale
 //----------------------------------------------------------------------------------------
 dcl-proc  FormatFieldDefinition;
     dcl-pi  FormatFieldDefinition  varchar(35);
         inType  varchar(10) const;
         inLength  int(10) const;
         inScale  int(10) const;
     end-pi;

     dcl-s  type  varchar(10);
     dcl-s  defn  varchar(35);

     type = inType;
     if type = 'TIMESTMP';
         type = 'TIMESTAMP';
     endif;

     defn = type;

     if type = 'BIGINT'
     or type = 'INTEGER'
     or type = 'SMALLINT'
     or type = 'DATE'
     or type = 'TIME'
     or type = 'TIMESTAMP';
         // nothing
     else;
         defn += '(' + %char(inLength);
         if inScale >= 0;
             defn += ' , ' + %char(inScale);
         endif;
         defn += ')';
     endif;

     return defn;

 end-proc  FormatFieldDefinition;


 //----------------------------------------------------------------------------------------
 // Add Identity Column
 // Adds an identity column definition to the DDL source.
 // This ASSUMES that the table doesn't already have one!
 //----------------------------------------------------------------------------------------
 dcl-proc  AddIdentityColumn;

     dcl-s  constraintName  varchar(35);

     WriteSource('   PRIMARY_KEY                          FOR COLUMN RCDNBR');
     WriteSource('       BIGINT                           GENERATED BY DEFAULT AS IDENTITY');
     WriteSource('                                        (START WITH 1, INCREMENT BY 1)');

     constraintName = %trim(inLib) + '_' + %trim(inNewFile) + '_ROW_ID_PK';
     WriteSource(',      CONSTRAINT ' + constraintName);
     WriteSource('         PRIMARY KEY(RCDNBR)');

     return;

 end-proc  AddIdentityColumn;


 //----------------------------------------------------------------------------------------
 // Add Metadata Columns
 // Adds create user/timestamp and row change timestamp
 //----------------------------------------------------------------------------------------
 dcl-proc  AddMetadataColumns;

     WriteSource(' ');
     WriteSource('/* metadata');
     WriteSource('-------------------------------------------------------------------------*/');
     WriteSource(', CREATE_USER                           FOR COLUMN CRTUSR        ');
     WriteSource('     CHAR(18)                           CCSID 37                 ');
     WriteSource('                                        NOT NULL                 ');
     WriteSource('                                        DEFAULT USER             ');
     WriteSource('                                                                 ');
     WriteSource(', CREATE_TS                             FOR COLUMN CRTTS         ');
     WriteSource('     TIMESTAMP                                                   ');
     WriteSource('                                        NOT NULL                 ');
     WriteSource('                                        DEFAULT CURRENT TIMESTAMP');
     WriteSource('                                                                 ');
     WriteSource(', CHANGE_TS                             FOR COLUMN CHGTS         ');
     WriteSource('     TIMESTAMP                          NOT NULL                 ');
     WriteSource('                                        FOR EACH ROW ON UPDATE   ');
     WriteSource('                                        AS ROW CHANGE TIMESTAMP  ');

     return;

 end-proc  AddMetadataColumns;




 //----------------------------------------------------------------------------------------
 // Create Table Clause
 // Formats the "CREATE TABLE" clause
 //----------------------------------------------------------------------------------------
 dcl-proc  CreateTableClause;

     dcl-s  tableName  varchar(128);
     dcl-s  tableText  char(50);   // this is actually VarGraph(100)

     Exec SQL
       SELECT table_text
       INTO :tableText
       FROM qsys2.systables
       WHERE system_table_schema = :inLib
         AND system_table_name = :inFile
         AND table_type = 'P';

     if sqlcode <> 0;
         SignalError('From file not found in SYSTABLES');
     endif;

     if tableText <> *blanks;
         tableName = %scanrpl(' ' : '_' : %trim(tableText));
     else;
         tableName = %trim(inNewFile);
     endif;

     // The SQL Name (ALIAS) must be > 10 characters
     if %len(tableName) < 11;
         tableName += '_SQL_NAME';
     endif;

     WriteSource('CREATE OR REPLACE TABLE ' + tableName);
     WriteSource('FOR SYSTEM NAME ' + inNewFile);

     return;

 end-proc  CreateTableClause;


 //----------------------------------------------------------------------------------------
 // Associate Result Set
 // GENERATE_SQL returns a result set containing the generated SQL.
 // This will associate that result set with a cursor that we can read.
 //----------------------------------------------------------------------------------------
 dcl-proc  AssociateResultSet;

   dcl-s  resultSetLocator   sqltype(RESULT_SET_LOCATOR);

   Exec SQL
     ASSOCIATE LOCATORS (:resultSetLocator)
     WITH PROCEDURE generate_sql;

   Exec SQL
     ALLOCATE generated_source CURSOR FOR
     RESULT SET :resultSetLocator;


   return;

 end-proc  AssociateResultSet;


 //----------------------------------------------------------------------------------------
 // Generate SQL
 // Calls the IBM provided procedure to generate SQL for a table.
 // This will put the DDL source into QTEMP/Q_GENSQL, Q_GENSQL.
 //----------------------------------------------------------------------------------------
 dcl-proc  GenerateSql;

   dcl-s  sql  varchar(2056);

   sql = 'CALL qsys2.generate_sql +
         ( DATABASE_OBJECT_LIBRARY_NAME => ''' + %trim(inLib) + ''' +
         , DATABASE_OBJECT_NAME => ''' + %trim(inFile) + ''' +
         , DATABASE_OBJECT_TYPE => ''TABLE'' +
         , STATEMENT_FORMATTING_OPTION => ''0'' +
         )';

   Exec SQL
    EXECUTE IMMEDIATE :sql;

   if sqlcode <> 466;
       SignalError('Unable to generate SQL.  Error ' + sqlstate);
   endif;

   return;

 end-proc  GenerateSql;

 //----------------------------------------------------------------------------------------
 // Create Source Members
 // Creates QTEMP/Q_GENSQL source file.
 // Creates QTEMP/QSQLSRC source file.
 // Add member for the DDL source (same name as existing file).
 //----------------------------------------------------------------------------------------
 dcl-proc  CreateSourceMembers;

   dcl-pr RunCommand  int(10)   extproc('system');
           *n         pointer   value  options(*string);
   end-pr;

   dcl-s  command  varchar(2056);

   // TODO:
   // Use IFS files instead of SRC-PF members.

   // We want to create Q_GENSQL manually because the default will only
   // have 80 columns.  Using 200 should prevent lines from wrapping
   // (which this program doesn't yet handle).
   // Quite tempted to make the record length 250 so that you can't
   // open it with SEU ...maybe next time...
   command = 'CRTSRCPF FILE(QTEMP/Q_GENSQL) RCDLEN(200) MBR(*NONE)';
   RunCommand(command);

   command = 'CRTSRCPF FILE(QTEMP/QSQLSRC) RCDLEN(200) MBR(*NONE)';
   RunCommand(command);

   command = 'ADDPFM FILE(QTEMP/QSQLSRC) MBR(' + %trim(inNewFile) + ') +
                     TEXT(''SQL Source for DDS to DDL conversion'') +
                     SRCTYPE(SQL)';
   RunCommand(command);

   command = 'CREATE OR REPLACE ALIAS qtemp/ddl_source +
              FOR QTEMP/QSQLSRC (' + %trim(inNewFile) + ')';

   Exec SQL
    EXECUTE IMMEDIATE :command;

   Exec SQL
    DELETE FROM qtemp/ddl_source
    WHERE 1=1;

   return;

 end-proc  CreateSourceMembers;


 //----------------------------------------------------------------------------------------
 // Write Source
 // Writes to the new DDL source member
 //----------------------------------------------------------------------------------------
 dcl-proc  WriteSource;
   dcl-pi  WriteSource;
       inSource  char(188) const;
   end-pi;

   Exec SQL
    INSERT INTO qtemp.ddl_source
    (SRCDTA)
    VALUES
    (:inSource);

   return;

 end-proc  WriteSource;



 //----------------------------------------------------------------------------------------
 // Starts With
 // Returns *ON if inSource begins with inSearch
 //----------------------------------------------------------------------------------------
 dcl-proc  StartsWith;
   dcl-pi  StartsWith  ind;
       inSource  varchar(2000) const;
       inSearch  varchar(2000) const;
   end-pi;

   return (%scan(inSearch : inSource : 1) = 1);

 end-proc  StartsWith;


 //----------------------------------------------------------------------------------------
 // Ends With
 // Returns *ON if the last non-blank character is a match
 //----------------------------------------------------------------------------------------
 dcl-proc  EndsWith;
   dcl-pi  EndsWith  ind;
       inSource  varchar(2000) const;
       inSearch  varchar(2000) const;
   end-pi;
   dcl-s  theyMatch ind;

   Exec SQL
       SET :theyMatch =
         CASE WHEN :inSource LIKE '%' CONCAT :inSearch
                  THEN '1'
              ELSE '0'  END;

   return theyMatch;
 end-proc  EndsWith;


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

