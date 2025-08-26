#!/bin/bash

# ==== USAGE =========
# ./mysql_backup_restore.sh backup
# ./mysql_backup_restore.sh restore /path/to/backup_file.sql

# === CONFIGURATION ===
DB_USER="addendum"
DB_PASS="g8u-yedu6565R8fjh-efJYH7f"
DB_NAME="prod_fav"
BACKUP_DIR="/home/rolandas-balkauskas/sql/backup"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="${BACKUP_DIR}/${DB_NAME}_${TIMESTAMP}.sql"

# === FUNCTIONS ===

backup_db() {
    echo "🔄 Backing up MySQL database '${DB_NAME}' to ${BACKUP_FILE}"
    mkdir -p "$BACKUP_DIR"
    mysqldump --routines --triggers --events --single-transaction "$DB_NAME" > "$BACKUP_FILE"

    if [[ $? -eq 0 ]]; then
        echo "✅ Backup successful!"
    else
        echo "❌ Backup failed!"
        exit 1
    fi
}

restore_db() {
    if [[ ! -f "$1" ]]; then
        echo "❌ Backup file '$1' not found!"
        exit 1
    fi

    # mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < "$1"
    # sed -i 's/NO_AUTO_CREATE_USER,//g' "$1"
    # sed -i 's/,NO_AUTO_CREATE_USER//g' "$1"
    # sed -i 's/NO_AUTO_CREATE_USER//g' "$1"
    # sed -i 's/DEFINER=`itree`@`%`/DEFINER=`addendum`@`%`/g' "$1" 
    # sed -i 's/DEFINER=`root`@`localhost`/DEFINER=`addendum`@`%`/g' "$1"
    echo "♻️  Dropping database '${DB_NAME}' from $1"
    mysql -e "DROP DATABASE $DB_NAME;"
    
    echo "♻️  Creating database '${DB_NAME}' from $1"
    mysql -e "CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    # mysql -e "CREATE DATABASE $DB_NAME;"
    
    echo "♻️  Restoring database '${DB_NAME}' from $1"
    mysql  "$DB_NAME" < "$1"

    if [[ $? -eq 0 ]]; then
        echo "✅ Restore successful!"
    else
        echo "❌ Restore failed!"
        exit 1
    fi
}

# === MAIN ===

case "$1" in
    backup)
        backup_db
        ;;
    restore)
        restore_db "$2"
        ;;
    *)
        echo "Usage: $0 {backup|restore <file.sql>}"
        exit 1
        ;;
esac
