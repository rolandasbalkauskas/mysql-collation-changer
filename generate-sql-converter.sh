#!/bin/bash

# Simple MySQL Character Set Migration SQL Generator
# This version uses temporary files to avoid quote handling issues
# Usage: ./simple_generate_sql.sh [database_name] [username] [password]

set -e  # Exit on any error

# Default parameters
DB_NAME=${1:-"prod_fav"}
DB_USER=${2:-"root"}
DB_PASS=${3:-""}
TARGET_CHARSET=${4:-"utf8mb4"}
TARGET_COLLATION=${5:-"utf8mb4_0900_ai_ci"}

# Output directory
# OUTPUT_DIR="mysql_migration_$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="mysql_migration"
rm -R "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# MySQL command prefix
MYSQL_CMD="mysql -u$DB_USER"
if [ ! -z "$DB_PASS" ]; then
    MYSQL_CMD="$MYSQL_CMD -p$DB_PASS"
fi

# Temporary directory for intermediate files
TEMP_DIR="/tmp/mysql_migration_$$"
mkdir -p "$TEMP_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
    chmod -R go+w "$OUTPUT_DIR"
}
trap cleanup EXIT

echo -e "${GREEN}Simple MySQL Character Set Migration SQL Generator${NC}"
echo -e "${BLUE}Database: $DB_NAME${NC}"
echo -e "${BLUE}Target Charset: $TARGET_CHARSET${NC}"
echo -e "${BLUE}Target Collation: $TARGET_COLLATION${NC}"
echo -e "${BLUE}Output Directory: $OUTPUT_DIR${NC}"
echo ""

# Function to check if database exists
check_database() {
    local db_exists
    db_exists=$($MYSQL_CMD -e "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$DB_NAME';" -N 2>/dev/null | wc -l)
    if [ "$db_exists" -eq 0 ]; then
        echo -e "${RED}Error: Database '$DB_NAME' does not exist!${NC}"
        exit 1
    fi
}

# Check database existence
echo -e "${YELLOW}Checking database existence...${NC}"
check_database

# 1. Generate DATABASE migration SQL
echo -e "${YELLOW}Generating database migration SQL...${NC}"
cat > "$OUTPUT_DIR/01_database_migration.sql" << 'EOF_DB'
-- Database Character Set Migration
-- Set session variables for consistency
SET NAMES utf8mb4 COLLATE utf8mb4_0900_ai_ci;
SET CHARACTER_SET_CLIENT = utf8mb4;
SET CHARACTER_SET_CONNECTION = utf8mb4;
SET CHARACTER_SET_RESULTS = utf8mb4;

-- Show current database character set
SELECT 'BEFORE MIGRATION - Current database character set:' as info;
EOF_DB

echo "SHOW CREATE DATABASE \`$DB_NAME\`;" >> "$OUTPUT_DIR/01_database_migration.sql"

cat >> "$OUTPUT_DIR/01_database_migration.sql" << 'EOF_DB2'

-- Change database default character set and collation
EOF_DB2

echo "ALTER DATABASE \`$DB_NAME\` CHARACTER SET = $TARGET_CHARSET COLLATE = $TARGET_COLLATION;" >> "$OUTPUT_DIR/01_database_migration.sql"

cat >> "$OUTPUT_DIR/01_database_migration.sql" << 'EOF_DB3'

-- Show new database character set
SELECT 'AFTER MIGRATION - New database character set:' as info;
EOF_DB3

echo "SHOW CREATE DATABASE \`$DB_NAME\`;" >> "$OUTPUT_DIR/01_database_migration.sql"




# 2. Generate TABLE migration SQL
echo -e "${YELLOW}Generating table migration SQL...${NC}"
cat > "$OUTPUT_DIR/02_tables_migration.sql" << 'EOF_TABLES'
-- Tables Character Set Migration
-- Disable foreign key checks to avoid constraint issues
SET FOREIGN_KEY_CHECKS = 0;

-- Show tables with current character sets
SELECT 'BEFORE MIGRATION - Current table character sets:' as info;
EOF_TABLES

echo "SELECT TABLE_NAME, TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;" >> "$OUTPUT_DIR/02_tables_migration.sql"

cat >> "$OUTPUT_DIR/02_tables_migration.sql" << 'EOF_TABLES2'

-- Show columns with current character sets
SELECT 'BEFORE MIGRATION - Current column character sets:' as info;
EOF_TABLES2

echo "SELECT TABLE_NAME, COLUMN_NAME, CHARACTER_SET_NAME, COLLATION_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = '$DB_NAME' AND CHARACTER_SET_NAME IS NOT NULL ORDER BY TABLE_NAME, ORDINAL_POSITION;" >> "$OUTPUT_DIR/02_tables_migration.sql"

echo "" >> "$OUTPUT_DIR/02_tables_migration.sql"
echo "-- Table conversion commands:" >> "$OUTPUT_DIR/02_tables_migration.sql"

# Generate table conversion commands using temporary file
$MYSQL_CMD -e "SELECT CONCAT('ALTER TABLE \`', TABLE_NAME, '\` CONVERT TO CHARACTER SET $TARGET_CHARSET COLLATE $TARGET_COLLATION;') FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;" -N > "$TEMP_DIR/table_conversions.sql" 2>/dev/null

if [ -f "$TEMP_DIR/table_conversions.sql" ]; then
    cat "$TEMP_DIR/table_conversions.sql" >> "$OUTPUT_DIR/02_tables_migration.sql"
fi

cat >> "$OUTPUT_DIR/02_tables_migration.sql" << 'EOF_TABLES3'

-- Re-enable foreign key checks
SET FOREIGN_KEY_CHECKS = 1;

-- Verify table conversions
SELECT 'AFTER MIGRATION - Verify table character sets:' as info;
EOF_TABLES3

echo "SELECT TABLE_NAME, TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME;" >> "$OUTPUT_DIR/02_tables_migration.sql"




# 3. Generate PROCEDURES files
echo -e "${YELLOW}Generating procedures migration SQL...${NC}"

# Get procedure names
$MYSQL_CMD -e "SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '$DB_NAME' AND ROUTINE_TYPE = 'PROCEDURE' ORDER BY ROUTINE_NAME;" -N > "$TEMP_DIR/procedure_names.txt" 2>/dev/null || touch "$TEMP_DIR/procedure_names.txt"

procedure_count=$(cat "$TEMP_DIR/procedure_names.txt" | wc -l)
if [ -s "$TEMP_DIR/procedure_names.txt" ]; then
    procedure_count=$(cat "$TEMP_DIR/procedure_names.txt" | grep -v '^$' | wc -l)
else
    procedure_count=0
fi

# Create procedure backup file
cat > "$OUTPUT_DIR/03_procedures_backup.sql" << 'EOF_PROC_BACKUP'
-- Stored Procedures Backup
-- List of current procedures
SELECT 'Current stored procedures:' as info;
EOF_PROC_BACKUP

echo "SELECT ROUTINE_NAME, CREATED, LAST_ALTERED FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '$DB_NAME' AND ROUTINE_TYPE = 'PROCEDURE' ORDER BY ROUTINE_NAME;" >> "$OUTPUT_DIR/03_procedures_backup.sql"

echo "" >> "$OUTPUT_DIR/03_procedures_backup.sql"

# Process each procedure
if [ "$procedure_count" -gt 0 ]; then
    echo "Processing $procedure_count procedures..."
    while IFS= read -r proc_name; do
        if [ ! -z "$proc_name" ]; then
            echo "  Processing procedure: $proc_name"
            echo "-- =============================================" >> "$OUTPUT_DIR/03_procedures_backup.sql"
            echo "-- Procedure: $proc_name" >> "$OUTPUT_DIR/03_procedures_backup.sql"
            echo "-- =============================================" >> "$OUTPUT_DIR/03_procedures_backup.sql"
            echo "SELECT '###### PROC - $proc_name #######';" >> "$OUTPUT_DIR/03_procedures_backup.sql"
            echo "DELIMITER \$\$" >> "$OUTPUT_DIR/03_procedures_backup.sql"
            
            # Get procedure definition using temporary file
            $MYSQL_CMD -e "SHOW CREATE PROCEDURE \`$DB_NAME\`.\`$proc_name\`;" -N > "$TEMP_DIR/proc_def.tmp" 2>/dev/null
            
            if [ -f "$TEMP_DIR/proc_def.tmp" ] && [ -s "$TEMP_DIR/proc_def.tmp" ]; then
                # Extract the definition (3rd column) and clean DEFINER
                # cut -f3 "$TEMP_DIR/proc_def.tmp" | sed 's/CREATE DEFINER[^*]*\*/CREATE */' >> "$OUTPUT_DIR/03_procedures_backup.sql"
                # cut -f3 "$TEMP_DIR/proc_def.tmp" >> "$OUTPUT_DIR/03_procedures_backup.sql"
                cut -f3 "$TEMP_DIR/proc_def.tmp" | sed 's/\\n/\n/g' | sed 's/\\t/    /g' >> "$OUTPUT_DIR/03_procedures_backup.sql"
            else
                echo "-- ERROR: Could not backup procedure $proc_name" >> "$OUTPUT_DIR/03_procedures_backup.sql"
                echo -e "${RED}Warning: Could not backup procedure $proc_name${NC}"
            fi
            
            echo "\$\$" >> "$OUTPUT_DIR/03_procedures_backup.sql"
            echo "DELIMITER ;" >> "$OUTPUT_DIR/03_procedures_backup.sql"
            echo "" >> "$OUTPUT_DIR/03_procedures_backup.sql"
        fi
    done < "$TEMP_DIR/procedure_names.txt"
else
    echo "-- No procedures found" >> "$OUTPUT_DIR/03_procedures_backup.sql"
fi

# Create procedure migration (drop) file
cat > "$OUTPUT_DIR/03_procedures_migration.sql" << 'EOF_PROC_MIG'
-- Stored Procedures Migration
-- Drop existing procedures
EOF_PROC_MIG

if [ "$procedure_count" -gt 0 ]; then
    $MYSQL_CMD -e "SELECT CONCAT('DROP PROCEDURE IF EXISTS \`', ROUTINE_NAME, '\`;') FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '$DB_NAME' AND ROUTINE_TYPE = 'PROCEDURE' ORDER BY ROUTINE_NAME;" -N >> "$OUTPUT_DIR/03_procedures_migration.sql" 2>/dev/null
else
    echo "-- No procedures to drop" >> "$OUTPUT_DIR/03_procedures_migration.sql"
fi

cat >> "$OUTPUT_DIR/03_procedures_migration.sql" << 'EOF_PROC_MIG2'

-- Recreate procedures with proper character set
-- Execute the definitions from 03_procedures_backup.sql after this script

-- Verify procedures after recreation
SELECT 'Procedures after migration:' as info;
EOF_PROC_MIG2

echo "SELECT ROUTINE_NAME, CREATED, LAST_ALTERED FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '$DB_NAME' AND ROUTINE_TYPE = 'PROCEDURE' ORDER BY ROUTINE_NAME;" >> "$OUTPUT_DIR/03_procedures_migration.sql"


# 4. Generate FUNCTIONS files (similar to procedures)
echo -e "${YELLOW}Generating functions migration SQL...${NC}"

# Get function names
$MYSQL_CMD -e "SELECT ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '$DB_NAME' AND ROUTINE_TYPE = 'FUNCTION' ORDER BY ROUTINE_NAME;" -N > "$TEMP_DIR/function_names.txt" 2>/dev/null || touch "$TEMP_DIR/function_names.txt"

if [ -s "$TEMP_DIR/function_names.txt" ]; then
    function_count=$(cat "$TEMP_DIR/function_names.txt" | grep -v '^$' | wc -l)
else
    function_count=0
fi

# Similar processing for functions...
cat > "$OUTPUT_DIR/04_functions_backup.sql" << 'EOF_FUNC'
-- Functions Backup
-- List of current functions
SELECT 'Current functions:' as info;
EOF_FUNC

echo "SELECT ROUTINE_NAME, CREATED, LAST_ALTERED, DTD_IDENTIFIER as RETURNS_TYPE FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '$DB_NAME' AND ROUTINE_TYPE = 'FUNCTION' ORDER BY ROUTINE_NAME;" >> "$OUTPUT_DIR/04_functions_backup.sql"

if [ "$function_count" -gt 0 ]; then
    echo "Processing $function_count functions..."
    while IFS= read -r func_name; do
        if [ ! -z "$func_name" ]; then
            echo "  Processing function: $func_name"
            echo "-- =============================================" >> "$OUTPUT_DIR/04_functions_backup.sql"
            echo "-- Function: $func_name" >> "$OUTPUT_DIR/04_functions_backup.sql"
            echo "-- =============================================" >> "$OUTPUT_DIR/04_functions_backup.sql"
            echo "SELECT '###### FUNC - $func_name #######';" >> "$OUTPUT_DIR/04_functions_backup.sql"
            echo "DELIMITER \$\$" >> "$OUTPUT_DIR/04_functions_backup.sql"
            
            $MYSQL_CMD -e "SHOW CREATE FUNCTION \`$DB_NAME\`.\`$func_name\`;" -N > "$TEMP_DIR/func_def.tmp" 2>/dev/null
            
            if [ -f "$TEMP_DIR/func_def.tmp" ] && [ -s "$TEMP_DIR/func_def.tmp" ]; then
                # cut -f3 "$TEMP_DIR/func_def.tmp" | sed 's/CREATE DEFINER[^*]*\*/CREATE */' >> "$OUTPUT_DIR/04_functions_backup.sql"
                # cut -f3 "$TEMP_DIR/func_def.tmp" >> "$OUTPUT_DIR/04_functions_backup.sql"
                cut -f3 "$TEMP_DIR/func_def.tmp" | sed 's/\\n/\n/g' | sed 's/\\t/    /g' | sed 's/CHARSET utf8mb3//g' | sed 's/CHARSET utf8mb4 COLLATE utf8mb4_unicode_ci//g' >> "$OUTPUT_DIR/04_functions_backup.sql"
            else
                echo "-- ERROR: Could not backup function $func_name" >> "$OUTPUT_DIR/04_functions_backup.sql"
            fi
            
            echo "\$\$" >> "$OUTPUT_DIR/04_functions_backup.sql"
            echo "DELIMITER ;" >> "$OUTPUT_DIR/04_functions_backup.sql"
            echo "" >> "$OUTPUT_DIR/04_functions_backup.sql"
        fi
    done < "$TEMP_DIR/function_names.txt"
else
    echo "-- No functions found" >> "$OUTPUT_DIR/04_functions_backup.sql"
fi

# Create function migration file
cat > "$OUTPUT_DIR/04_functions_migration.sql" << 'EOF_FUNC_MIG'
-- Functions Migration  
-- Drop existing functions
EOF_FUNC_MIG

if [ "$function_count" -gt 0 ]; then
    $MYSQL_CMD -e "SELECT CONCAT('DROP FUNCTION IF EXISTS \`', ROUTINE_NAME, '\`;') FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '$DB_NAME' AND ROUTINE_TYPE = 'FUNCTION' ORDER BY ROUTINE_NAME;" -N >> "$OUTPUT_DIR/04_functions_migration.sql" 2>/dev/null
else
    echo "-- No functions to drop" >> "$OUTPUT_DIR/04_functions_migration.sql"
fi


# 5. Generate TRIGGERS files (similar to procedures)
echo -e "${YELLOW}Generating triggers migration SQL...${NC}"

# Get triggers names
$MYSQL_CMD -e "SELECT TRIGGER_NAME FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = '$DB_NAME' ORDER BY EVENT_OBJECT_TABLE, TRIGGER_NAME;" -N > "$TEMP_DIR/trigger_names.txt" 2>/dev/null || touch "$TEMP_DIR/trigger_names.txt"

if [ -s "$TEMP_DIR/trigger_names.txt" ]; then
    trigger_count=$(cat "$TEMP_DIR/trigger_names.txt" | grep -v '^$' | wc -l)
else
    trigger_count=0
fi

# Similar processing for triggers...
cat > "$OUTPUT_DIR/05_triggers_backup.sql" << 'EOF_FUNC'
-- Functions Backup
-- List of current triggers
SELECT 'Current triggers:' as info;
EOF_FUNC

echo "SELECT TRIGGER_NAME, EVENT_OBJECT_TABLE, CREATED  FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = '$DB_NAME' ORDER BY EVENT_OBJECT_TABLE, TRIGGER_NAME;" >> "$OUTPUT_DIR/05_triggers_backup.sql"

if [ "$trigger_count" -gt 0 ]; then
    echo "Processing $trigger_count triggers..."
    while IFS= read -r trigg_name; do
        if [ ! -z "$trigg_name" ]; then
            echo "  Processing trigger: $trigg_name"
            echo "-- =============================================" >> "$OUTPUT_DIR/05_triggers_backup.sql"
            echo "-- Function: $trigg_name" >> "$OUTPUT_DIR/05_triggers_backup.sql"
            echo "-- =============================================" >> "$OUTPUT_DIR/05_triggers_backup.sql"
            echo "SELECT '###### TRIG - $trigg_name #######';" >> "$OUTPUT_DIR/05_triggers_backup.sql"
            echo "DELIMITER \$\$" >> "$OUTPUT_DIR/05_triggers_backup.sql"
            
            $MYSQL_CMD -e "SHOW CREATE TRIGGER \`$DB_NAME\`.\`$trigg_name\`;" -N > "$TEMP_DIR/trigg_def.tmp" 2>/dev/null
            
            if [ -f "$TEMP_DIR/trigg_def.tmp" ] && [ -s "$TEMP_DIR/trigg_def.tmp" ]; then
                # cut -f3 "$TEMP_DIR/trigg_def.tmp" | sed 's/CREATE DEFINER[^*]*\*/CREATE */' >> "$OUTPUT_DIR/05_triggers_backup.sql"
                # cut -f3 "$TEMP_DIR/trigg_def.tmp" >> "$OUTPUT_DIR/05_triggers_backup.sql"
                cut -f3 "$TEMP_DIR/trigg_def.tmp" | sed 's/\\n/\n/g' | sed 's/\\t/    /g' >> "$OUTPUT_DIR/05_triggers_backup.sql"
            else
                echo "-- ERROR: Could not backup trigger $trigg_name" >> "$OUTPUT_DIR/05_triggers_backup.sql"
            fi
            
            echo "\$\$" >> "$OUTPUT_DIR/05_triggers_backup.sql"
            echo "DELIMITER ;" >> "$OUTPUT_DIR/05_triggers_backup.sql"
            echo "" >> "$OUTPUT_DIR/05_triggers_backup.sql"
        fi
    done < "$TEMP_DIR/trigger_names.txt"
else
    echo "-- No triggers found" >> "$OUTPUT_DIR/05_triggers_backup.sql"
fi

# Create trigger migration file
cat > "$OUTPUT_DIR/05_triggers_migration.sql" << 'EOF_FUNC_MIG'
-- Functions Migration  
-- Drop existing triggers
EOF_FUNC_MIG

if [ "$trigger_count" -gt 0 ]; then
    $MYSQL_CMD -e "SELECT CONCAT('DROP TRIGGER IF EXISTS \`', TRIGGER_NAME, '\`;') FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = '$DB_NAME' ORDER BY EVENT_OBJECT_TABLE, TRIGGER_NAME;" -N >> "$OUTPUT_DIR/05_triggers_migration.sql" 2>/dev/null
else
    echo "-- No triggers to drop" >> "$OUTPUT_DIR/05_triggers_migration.sql"
fi



# 6. Generate simple README
cat > "$OUTPUT_DIR/README.md" << EOF
# MySQL Character Set Migration Files

Generated for database: **$DB_NAME**
Target character set: **$TARGET_CHARSET**  
Target collation: **$TARGET_COLLATION**
Generated on: $(date)

## Object Counts
- Procedures: $procedure_count
- Functions: $function_count
- Triggers: $trigger_count

## Execution Order

1. **Database Migration:**
   \`\`\`bash
   mysql -u$DB_USER -p $DB_NAME < 01_database_migration.sql
   \`\`\`

2. **Tables Migration:**
   \`\`\`bash
   mysql -u$DB_USER -p $DB_NAME < 02_tables_migration.sql
   \`\`\`

3. **Procedures (Drop then Recreate):**
   \`\`\`bash
   mysql -u$DB_USER -p $DB_NAME < 03_procedures_migration.sql
   mysql -u$DB_USER -p $DB_NAME < 03_procedures_backup.sql
   \`\`\`

4. **Functions (Drop then Recreate):**
   \`\`\`bash
   mysql -u$DB_USER -p $DB_NAME < 04_functions_migration.sql  
   mysql -u$DB_USER -p $DB_NAME < 04_functions_backup.sql
   \`\`\`

5. **Triggers (Drop then Recreate):**
   \`\`\`bash
   mysql -u$DB_USER -p $DB_NAME < 05_triggers_migration.sql  
   mysql -u$DB_USER -p $DB_NAME < 05_triggers_backup.sql
   \`\`\`

## Execution in mysql console
\`\`\`sql
tee mysql-cli.log
source 01_database_migration.sql
source 02_tables_migration.sql
source 03_procedures_migration.sql
source 03_procedures_backup.sql
source 04_functions_migration.sql 
source 04_functions_backup.sql
source 05_triggers_migration.sql 
source 05_triggers_backup.sql
\`\`\`

## Important Notes
- Always backup your database before running these scripts
- Review the backup files before executing them
- Test in a development environment first
EOF

echo -e "${GREEN}SQL files generation completed successfully!${NC}"
echo -e "${BLUE}Output directory: $OUTPUT_DIR${NC}"
echo ""
echo -e "${YELLOW}Generated files:${NC}"
echo "  01_database_migration.sql     - Database character set changes"
echo "  02_tables_migration.sql       - Table conversions"
echo "  03_procedures_migration.sql   - Drop procedures"
echo "  03_procedures_backup.sql      - Procedure definitions to recreate"
echo "  04_functions_migration.sql    - Drop functions"
echo "  04_functions_backup.sql       - Function definitions to recreate"
echo "  05_triggers_migration.sql     - Drop triggers"
echo "  05_triggers_backup.sql        - Trigger definitions to recreate"
echo "  README.md                     - Execution instructions"
echo ""
echo -e "${YELLOW}Object counts:${NC}"
echo "  Procedures: $procedure_count"
echo "  Functions: $function_count"
echo "  Triggers: $trigger_count"
echo ""
echo -e "${YELLOW}MySQL CLI commands:${NC}"
echo "  tee mysql-cli.log"
echo "  source 01_database_migration.sql"
echo "  source 02_tables_migration.sql"
echo "  source 03_procedures_migration.sql"
echo "  source 03_procedures_backup.sql"
echo "  source 04_functions_migration.sql"
echo "  source 04_functions_backup.sql"
echo "  source 05_triggers_migration.sql"
echo "  source 05_triggers_backup.sql"
echo ""
echo -e "${GREEN}Ready to execute!${NC}"