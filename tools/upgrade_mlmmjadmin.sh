#!/usr/bin/env bash

# Purpose: Upgrade mlmmjadmin from old release.

# USAGE:
#
#   Run commands below as root user:
#
#       # bash upgrade_mlmmjadmin.sh
#

export SYS_USER_MLMMJ='mlmmj'
export SYS_GROUP_MLMMJ='mlmmj'
export SYS_USER_ROOT='root'

# iRedAdmin directory and config file.
export MA_ROOT_DIR='/opt/mlmmjadmin'
export MA_PARENT_DIR="$(dirname ${MA_ROOT_DIR})"
export MA_CONF="${MA_ROOT_DIR}/settings.py"
export MA_CUSTOM_CONF="${MA_ROOT_DIR}/custom_settings.py"

# Path to some programs.
export CMD_PYTHON3='/usr/bin/python3'
export CMD_PIP3='/usr/bin/pip3'

# Check OS to detect some necessary info.
export KERNEL_NAME="$(uname -s | tr '[a-z]' '[A-Z]')"

if [ X"${KERNEL_NAME}" == X'LINUX' ]; then
    # systemd
    export USE_SYSTEMD='YES'
    export SYSTEMD_SERVICE_DIR='/lib/systemd/system'
    export SYSTEMD_SERVICE_DIR2='/etc/systemd/system'
    export SYSTEMD_SERVICE_USER_DIR='/etc/systemd/system/multi-user.target.wants/'


    if [ -f /etc/redhat-release ]; then
        # RHEL/CentOS
        export DISTRO='RHEL'

        # Get distribution version
        if grep '\ 8' /etc/redhat-release &>/dev/null; then
            export DISTRO_VERSION='8'
            export PYTHON_VER='38'
            export CMD_PIP3='/usr/bin/pip3.8'
            # uwsgi plugin is not required since uwsgi is installed with pip.
        elif grep '\ 7' /etc/redhat-release &>/dev/null; then
            export DISTRO_VERSION='7'
            export PYTHON_VER='36'
            export UWSGI_PY3_PLUGIN_NAME='python36'
        else
            export UNSUPPORTED_RELEASE="YES"
        fi
    elif [ -f /etc/lsb-release ]; then
        # Ubuntu
        export DISTRO='UBUNTU'

        # Ubuntu version number and code name:
        #   - 18.04: bionic
        #   - 20.04: focal
        export DISTRO_VERSION="$(awk -F'=' '/^DISTRIB_RELEASE/ {print $2}' /etc/lsb-release)"
        export DISTRO_CODENAME="$(awk -F'=' '/^DISTRIB_CODENAME/ {print $2}' /etc/lsb-release)"

        if [ X"${DISTRO_CODENAME}" == X'focal' ]; then
            # Ubuntu 20.04: Installed with pip2.
            export CMD_UWSGI='/usr/local/bin/uwsgi'
            export UWSGI_PY3_PLUGIN_NAME='python38'
        elif [ X"${DISTRO_CODENAME}" == X'bionic' ]; then
            # Ubuntu 18.04
            export UWSGI_PY3_PLUGIN_NAME='python36'
        else
            export UNSUPPORTED_RELEASE="YES"
        fi
    elif [ -f /etc/debian_version ]; then
        # Debian
        export DISTRO='DEBIAN'

        # Set distro code name and unsupported releases.
        if grep -i '^10' /etc/debian_version &>/dev/null; then
            export DISTRO_VERSION='10'
            export UWSGI_PY3_PLUGIN_NAME='python37'
        elif grep '^9' /etc/debian_version &>/dev/null || \
            grep -i '^stretch' /etc/debian_version &>/dev/null; then
            export DISTRO_VERSION='9'
            export UWSGI_PY3_PLUGIN_NAME='python35'
        else
            export UNSUPPORTED_RELEASE="YES"
        fi
    else
        echo "<<< ERROR >>> Cannot detect Linux distribution name. Exit."
        echo "<<< ERROR >>> Please contact support@iredmail.org to solve it."
        exit 255
    fi
elif [ X"${KERNEL_NAME}" == X'FREEBSD' ]; then
    export DISTRO='FREEBSD'
    export DIR_RC_SCRIPTS='/usr/local/etc/rc.d'
    export CMD_PYTHON3='/usr/local/bin/python3'
    export CMD_PIP3='/usr/local/bin/pip3'
elif [ X"${KERNEL_NAME}" == X'OPENBSD' ]; then
    export DISTRO='OPENBSD'
    export DIR_RC_SCRIPTS='/etc/rc.d'
    export CMD_PYTHON3='/usr/local/bin/python3'
    export CMD_PIP3='/usr/local/bin/pip3'

    if [ -x ${CMD_PIP3} ]; then
        :
    else
        for version in 3.7 3.6 3.5; do
            if [ -x /usr/local/bin/pip${version} ]; then
                export CMD_PIP3="/usr/local/bin/pip${version}"
                break
            fi
        done
    fi
else
    echo "Cannot detect Linux/BSD distribution. Exit."
    echo "Please contact author iRedMail team <support@iredmail.org> to solve it."
    exit 255
fi

if [ X"${UNSUPPORTED_RELEASE}" == X'YES' ]; then
    echo "Unsupported Linux/BSD distribution or release, abort."
    exit 255
fi

if [[ -d /etc/postfix/mysql ]] || [[ -d /usr/local/etc/postfix/mysql ]]; then
    export IREDMAIL_BACKEND='MYSQL'
elif [[ -d /etc/postfix/pgsql ]] || [[ -d /usr/local/etc/postfix/pgsql ]]; then
    export IREDMAIL_BACKEND='PGSQL'
elif [[ -d /etc/postfix/ldap ]] || [[ -d /usr/local/etc/postfix/ldap ]]; then
    export IREDMAIL_BACKEND='LDAP'
else
    echo "Can not detect iRedMail backend (MySQL, PostgreSQL, OpenLDAP). Abort."
    exit 255
fi

install_pkgs()
{
    echo "Install package: $@"

    if [ X"${DISTRO}" == X'RHEL' ]; then
        yum -y install $@
    elif [ X"${DISTRO}" == X'DEBIAN' -o X"${DISTRO}" == X'UBUNTU' ]; then
        apt-get install -y $@
    elif [ X"${DISTRO}" == X'FREEBSD' ]; then
        echo "Install package: ${_port}"
        cd /usr/ports/$@
        make USES=python:3.5+ install clean
    elif [ X"${DISTRO}" == X'OPENBSD' ]; then
        pkg_add -r $@
    else
        echo "<< ERROR >> Failed to install package, please install it manually: $@"
        exit 255
    fi
}

has_python_module()
{
    for mod in $@; do
        ${CMD_PYTHON3} -c "import $mod" &>/dev/null
        if [ X"$?" == X'0' ]; then
            echo 'YES'
        else
            echo 'NO'
        fi
    done
}

restart_mlmmjadmin()
{
    echo "* Restarting service: mlmmjadmin."
    if [ X"${KERNEL_NAME}" == X'LINUX' -o X"${KERNEL_NAME}" == X'FREEBSD' ]; then
        service mlmmjadmin restart
    elif [ X"${KERNEL_NAME}" == X'OPENBSD' ]; then
        rcctl restart mlmmjadmin
    fi

    if [ X"$?" != X'0' ]; then
        echo "Failed, please restart service 'mlmmjadmin' manually."
    fi
}

echo "* Detected Linux/BSD distribution: ${DISTRO}"

#
# Check dependent packages. Prompt to install missed ones manually.
#
DEP_PKGS=""
DEP_PIP3_MODS=""

# Install python3.
echo "* Checking Python 3."
if [ ! -x ${CMD_PYTHON3} ]; then
    if [ X"${DISTRO}" == X'RHEL' ]; then
        [[ X"${DISTRO_VERSION}" == X'7' ]] && DEP_PKGS="${DEP_PKGS} python3 python3-pip"
        [[ X"${DISTRO_VERSION}" == X'8' ]] && DEP_PKGS="${DEP_PKGS} python38 python38-pip"
    fi

    [ X"${DISTRO}" == X'DEBIAN' ]   && DEP_PKGS="${DEP_PKGS} python3 python3-pip"
    [ X"${DISTRO}" == X'UBUNTU' ]   && DEP_PKGS="${DEP_PKGS} python3 python3-pip"
    [ X"${DISTRO}" == X'FREEBSD' ]  && DEP_PKGS="${DEP_PKGS} lang/python38 devel/py-pip"

    if [ X"${DISTRO}" == X'OPENBSD' ]; then
        # Create symbol link.
        for v in 3.7 3.6 3.5 3.4; do
            if [ -x /usr/local/bin/python${v} ]; then
                ln -sf /usr/local/bin/python${v} /usr/local/bin/python3
                break
            fi
        done

        if [ ! -x ${CMD_PYTHON3} ]; then
            # OpenBSD 6.6, 6.7 should use Python 3.7 because all `py3-*` binary
            # packages were built against Python 3.7.
            DEP_PKGS="${DEP_PKGS} python%3.7"
        fi
    fi
fi

if [ ! -x ${CMD_PIP3} ]; then
    if [ X"${DISTRO}" == X'RHEL' ]; then
        [[ X"${DISTRO_VERSION}" == X'7' ]] && DEP_PKGS="${DEP_PKGS} python3-pip"
        [[ X"${DISTRO_VERSION}" == X'8' ]] && DEP_PKGS="${DEP_PKGS} python38-pip"
    fi

    [ X"${DISTRO}" == X'DEBIAN' ]   && DEP_PKGS="${DEP_PKGS} python3-pip"
    [ X"${DISTRO}" == X'UBUNTU' ]   && DEP_PKGS="${DEP_PKGS} python3-pip"
    [ X"${DISTRO}" == X'FREEBSD' ]  && DEP_PKGS="${DEP_PKGS} devel/py-pip"
    [ X"${DISTRO}" == X'OPENBSD' ]  && DEP_PKGS="${DEP_PKGS} py3-pip"
fi

echo "* Checking dependent Python modules:"

if [[ X"${IREDMAIL_BACKEND}" == X'MYSQL' ]]; then
    # MySQL/MariaDB backend
    echo "  + [required] pymysql"
    if [ X"$(has_python_module pymysql)" == X'NO' ]; then
        if [ X"${DISTRO}" == X'RHEL' ]; then
            if [ X"${DISTRO_VERSION}" == X'7' ]; then
                DEP_PKGS="${DEP_PKGS} python36-PyMySQL"
            else
                DEP_PKGS="${DEP_PKGS} python3-PyMySQL"
            fi
        fi

        [ X"${DISTRO}" == X'DEBIAN' ]   && DEP_PKGS="${DEP_PKGS} python3-pymysql"
        [ X"${DISTRO}" == X'UBUNTU' ]   && DEP_PKGS="${DEP_PKGS} python3-pymysql"
        [ X"${DISTRO}" == X'FREEBSD' ]  && DEP_PKGS="${DEP_PKGS} databases/py-pymysql"
        [ X"${DISTRO}" == X'OPENBSD' ]  && DEP_PKGS="${DEP_PKGS} py3-mysqlclient"
    fi
elif [[ X"${IREDMAIL_BACKEND}" == X'PGSQL' ]]; then
    # PostgreSQL backend
    echo "  + [required] psycopg2"
    if [ X"$(has_python_module psycopg2)" == X'NO' ]; then
        if [ X"${DISTRO}" == X'RHEL' ]; then
            if [ X"${DISTRO_VERSION}" == X'7' ]; then
                DEP_PKGS="${DEP_PKGS} python36-psycopg2"
            else
                DEP_PKGS="${DEP_PKGS} python3-psycopg2"
            fi
        fi

        [ X"${DISTRO}" == X'DEBIAN' ]   && DEP_PKGS="${DEP_PKGS} python3-psycopg2"
        [ X"${DISTRO}" == X'UBUNTU' ]   && DEP_PKGS="${DEP_PKGS} python3-psycopg2"
        [ X"${DISTRO}" == X'FREEBSD' ]  && DEP_PKGS="${DEP_PKGS} databases/py-psycopg2"
        [ X"${DISTRO}" == X'OPENBSD' ]  && DEP_PKGS="${DEP_PKGS} py3-psycopg2"
    fi
elif [[ X"${IREDMAIL_BACKEND}" == X'LDAP' ]]; then
    # LDAP backend
    if [ X"$(has_python_module ldap)" == X'NO' ]; then
        if [ X"${DISTRO}" == X'RHEL' ]; then
            if [ X"${DISTRO_VERSION}" == X'7' ]; then
                DEP_PKGS="${DEP_PKGS} python36-PyMySQL openldap-devel"
                DEP_PIP3_MODS="${DEP_PIP3_MODS} python-ldap>=3.3.0"
            else
                DEP_PKGS="${DEP_PKGS} python3-ldap python3-PyMySQL"
            fi
        fi

        if [ X"${DISTRO}" == X'DEBIAN' ]; then
            DEP_PKGS="${DEP_PKGS} python3-pymysql"
            if [ X"${DISTRO_VERSION}" == X'9' ]; then
                DEP_PKGS="${DEP_PKGS} python3-pyldap"
            else
                DEP_PKGS="${DEP_PKGS} python3-ldap"
            fi
        fi

        [ X"${DISTRO}" == X'UBUNTU' ]   && DEP_PKGS="${DEP_PKGS} python3-ldap python3-pymysql"
        [ X"${DISTRO}" == X'FREEBSD' ]  && DEP_PKGS="${DEP_PKGS} net/py-ldap databases/py-pymysql"
        [ X"${DISTRO}" == X'OPENBSD' ]  && DEP_PKGS="${DEP_PKGS} py3-ldap py3-mysqlclient"
    fi
fi


echo "  + [required] requests"
if [ X"$(has_python_module requests)" == X'NO' ]; then
    if [ X"${DISTRO}" == X'RHEL' ]; then
        [ X"${DISTRO_VERSION}" == X'7' ] && DEP_PKGS="${DEP_PKGS} python36-requests"
        [ X"${DISTRO_VERSION}" == X'8' ] && DEP_PKGS="${DEP_PKGS} python3-requests"
    fi

    [ X"${DISTRO}" == X'DEBIAN' ]   && DEP_PKGS="${DEP_PKGS} python3-requests"
    [ X"${DISTRO}" == X'UBUNTU' ]   && DEP_PKGS="${DEP_PKGS} python3-requests"
    [ X"${DISTRO}" == X'FREEBSD' ]  && DEP_PKGS="${DEP_PKGS} dns/py-requests"
    [ X"${DISTRO}" == X'OPENBSD' ]  && DEP_PKGS="${DEP_PKGS} py3-requests"
fi

echo "  + [required] web.py"
if [ X"$(has_python_module web)" == X'NO' ]; then
    # FreeBSD ports has 0.40. So we install the latest with pip.
    DEP_PIP3_MODS="${DEP_PIP3_MODS} web.py>=0.51"
fi

if [ X"${DEP_PKGS}" != X'' ]; then
    install_pkgs ${DEP_PKGS}

    if [ X"$?" != X'0' ]; then
        echo "<<< ERROR >>> Failed to install required packages, please try to install them manually: ${DEP_PKGS}"
        exit 255
    fi
fi

if [ X"${DEP_PIP3_MODS}" != X'' ]; then
    ${CMD_PIP3} install -U ${DEP_PIP3_MODS}

    if [ X"$?" != X'0' ]; then
        echo "<<< ERROR >>> Failed to install Python 3 modules, please try to install them manually: ${DEP_PIP3_MODS}"
        exit 255
    fi
fi


if [ -L ${MA_ROOT_DIR} ]; then
    export MA_ROOT_REAL_DIR="$(readlink ${MA_ROOT_DIR})"
    echo "* Found mlmmjadmin: ${MA_ROOT_DIR}, symbol link of ${MA_ROOT_REAL_DIR}"
else
    echo "<<< ERROR >>> Directory (${MA_ROOT_DIR}) is not a symbol link created by iRedMail. Exit."
    exit 255
fi

# Copy config file
if [ -f ${MA_CONF} ]; then
    echo "* Found old config file: ${MA_CONF}"
else
    echo "<<< ERROR >>> No old config file found ${MA_CONF}, exit."
    exit 255
fi

# Copy current directory to /opt
dir_new_version="$(dirname ${PWD})"
name_new_version="$(basename ${dir_new_version})"
NEW_MA_ROOT_DIR="${MA_PARENT_DIR}/${name_new_version}"
NEW_MA_CONF="${NEW_MA_ROOT_DIR}/settings.py"
if [ -d ${NEW_MA_ROOT_DIR} ]; then
    COPY_FILES="${dir_new_version}/*"
    COPY_DEST_DIR="${NEW_MA_ROOT_DIR}"
else
    COPY_FILES="${dir_new_version}"
    COPY_DEST_DIR="${MA_PARENT_DIR}"
fi

echo "* Copying new version to ${NEW_MA_ROOT_DIR}"
cp -rf ${COPY_FILES} ${COPY_DEST_DIR}

# Copy old config files
echo "* Copy ${MA_CONF}."
cp -p ${MA_CONF} ${NEW_MA_ROOT_DIR}/

if [ -f ${MA_CUSTOM_CONF} ]; then
    echo "* Copy ${MA_CUSTOM_CONF}."
    cp -p ${MA_CUSTOM_CONF} ${NEW_MA_ROOT_DIR}
fi

# Set owner and permission.
chown -R ${SYS_USER_MLMMJ}:${SYS_GROUP_MLMMJ} ${NEW_MA_ROOT_DIR}
chmod -R 0755 ${NEW_MA_ROOT_DIR}
chmod 0400 ${NEW_MA_CONF}

echo "* Removing old symbol link ${MA_ROOT_DIR}"
rm -f ${MA_ROOT_DIR}

echo "* Creating symbol link: ${NEW_MA_ROOT_DIR} -> ${MA_ROOT_DIR}"
cd ${MA_PARENT_DIR}
ln -s ${NEW_MA_ROOT_DIR} ${MA_ROOT_DIR}

# Always copy systemd or sysv script.
if [ X"${USE_SYSTEMD}" == X'YES' ]; then
    rm -f /etc/init.d/mlmmjadmin &>/dev/null
    rm -f ${SYSTEMD_SERVICE_DIR}/mlmmjadmin.service &>/dev/null
    rm -f ${SYSTEMD_SERVICE_DIR2}/mlmmjadmin.service &>/dev/null
    rm -f ${SYSTEMD_SERVICE_USER_DIR}/mlmmjadmin.service &>/dev/null

    echo "* Copy systemd service file."

    if [ X"${DISTRO}" == X'RHEL' ]; then
        cp -vf ${MA_ROOT_DIR}/rc_scripts/systemd/rhel.service ${SYSTEMD_SERVICE_DIR}/mlmmjadmin.service
        if [ X"${UWSGI_PY3_PLUGIN_NAME}" != X'' ]; then
            perl -pi -e 's#(^plugins.*)python,(.*)#${1}$ENV{UWSGI_PY3_PLUGIN_NAME},${2}#g' ${MA_ROOT_DIR}/rc_scripts/uwsgi/rhel.ini
        fi
    elif [ X"${DISTRO}" == X'DEBIAN' -o X"${DISTRO}" == X'UBUNTU' ]; then
        cp -vf ${MA_ROOT_DIR}/rc_scripts/systemd/debian.service ${SYSTEMD_SERVICE_DIR}/mlmmjadmin.service
        if [ X"${UWSGI_PY3_PLUGIN_NAME}" != X'' ]; then
            perl -pi -e 's#(^plugins.*)python,(.*)#${1}$ENV{UWSGI_PY3_PLUGIN_NAME},${2}#g' ${MA_ROOT_DIR}/rc_scripts/uwsgi/debian.ini
        fi
    fi

    chmod -R 0644 ${SYSTEMD_SERVICE_DIR}/mlmmjadmin.service
    systemctl daemon-reload &>/dev/null
    systemctl enable mlmmjadmin.service >/dev/null
else
    if [ -f "${DIR_RC_SCRIPTS}/mlmmjadmin" ]; then
        echo "* Copy SysV init script."

        if [ X"${DISTRO}" == X"FREEBSD" ]; then
            cp ${MA_ROOT_DIR}/rc_scripts/mlmmjadmin.freebsd ${DIR_RC_SCRIPTS}/mlmmjadmin
        elif [ X"${DISTRO}" == X'OPENBSD' ]; then
            cp ${MA_ROOT_DIR}/rc_scripts/mlmmjadmin.openbsd ${DIR_RC_SCRIPTS}/mlmmjadmin
        fi

        chmod 0755 ${DIR_RC_SCRIPTS}/mlmmjadmin
    fi
fi

# For systems which use systemd
systemctl daemon-reload &>/dev/null

echo "* mlmmjadmin has been successfully upgraded."
restart_mlmmjadmin

# Clean up.
cd ${NEW_MA_ROOT_DIR}/
rm -f settings.py{c,o} tools/settings.py{,c,o}

echo "* Upgrading completed."

cat <<EOF
<<< NOTE >>> If mlmmjadmin doesn't work as expected, please post your issue in
<<< NOTE >>> our online support forum: http://www.iredmail.org/forum/
EOF
