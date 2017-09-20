#!/bin/bash -x

# Настройка необходимых пакетов
# ----------------------------------

# Пакеты будут скачены с "$url"
url="https://update.cryptopro.ru/support/nginx-gost"

revision_openssl="161714"
pcre_ver="pcre-8.41"
zlib_ver="zlib-1.2.11"

# Версия nginx для загрузки с github
nginx_branch="stable-1.12"

if [ -n "$1" ] 
then    
    csp=$1
else
    printf "No argument (CSP)"
    exit 0
fi

cat /etc/*release* | grep -Ei "(centos|red hat)"
if [ "$?" -eq 0 ] 
then
    apt="yum"
    pkgmsys="rpm"
    pkglist="rpm -qa"
    install="rpm -i"
    openssl_packages=(cprocsp-cpopenssl-110-64_4.0.0-5_amd64.rpm \
    cprocsp-cpopenssl-110-base_4.0.0-5_all.rpm \
    cprocsp-cpopenssl-110-devel_4.0.0-5_all.rpm \
    cprocsp-cpopenssl-110-gost-64_4.0.0-5_amd64.rpm)

    modules_path=/usr/lib64/nginx/modules
    cc_ld_opt=" --with-cc-opt='-O2 -g -pipe -Wall -Wp,-D_FORTIFY_SOURCE=2 -fexceptions -fstack-protector --param=ssp-buffer-size=4 -m64 -mtune=generic -fPIC' --with-ld-opt='-Wl,-z,relro -Wl,-z,now -pie'" 

else
    cat /etc/*release* | grep -Ei "(ubuntu)"
    if [ "$?" -eq 0 ] 
    then
        apt="apt-get"
        pkgmsys="deb"
        pkglist="dpkg-query --list"
        install="dpkg -i"
        openssl_packages=(cprocsp-cpopenssl-110-64_4.0.0-5_amd64.deb \
        cprocsp-cpopenssl-110-base_4.0.0-5_all.deb \
        cprocsp-cpopenssl-110-devel_4.0.0-5_all.deb \
        cprocsp-cpopenssl-110-gost-64_4.0.0-5_amd64.deb)

        modules_path=/usr/lib/nginx/modules
        cc_ld_opt=" --with-cc-opt='-g -O2 -fstack-protector --param=ssp-buffer-size=4 -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC' --with-ld-opt='-Wl,-Bsymbolic-functions -Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie'"
    else
        printf "Not supported system (supported: Ubuntu, CentOS, Red Hat)."
        exit 0
    fi
fi

prefix=/etc/nginx
sbin_path=/usr/sbin/nginx
conf_path=/etc/nginx/nginx.conf
err_log_path=/var/log/nginx/error.log
http_log_path=/var/log/nginx/access.log
pid_path=/var/run/nginx.pid
lock_path=/var/run/nginx.lock
http_client_body_temp_path=/var/cache/nginx/client_temp
http_proxy_temp_path=/var/cache/nginx/proxy_temp
http_fastcgi_temp_path=/var/cache/nginx/fastcgi_temp
http_uwsgi_temp_path=/var/cache/nginx/uwsgi_temp
http_scgi_temp_path=/var/cache/nginx/scgi_temp
user=root
group=nginx


# ----------------------------------

# Настройка установочной конфигурации nginx
# ----------------------------------


nginx_paths=" --prefix=${prefix} --sbin-path=${sbin_path} --modules-path=${modules_path} --conf-path=${conf_path} --error-log-path=${err_log_path} --http-log-path=${http_log_path} --http-client-body-temp-path=${http_client_body_temp_path} --http-proxy-temp-path=${http_proxy_temp_path} --http-fastcgi-temp-path=${http_fastcgi_temp_path} --http-uwsgi-temp-path=${http_uwsgi_temp_path} --http-scgi-temp-path=${http_scgi_temp_path} --pid-path=${pid_path} --lock-path=${lock_path}"

nginx_parametrs=" --user=${user} --group=${group} --user=nginx --group=nginx --with-compat --with-file-aio --with-threads --with-http_addition_module --with-http_auth_request_module --with-http_dav_module --with-http_flv_module --with-http_gunzip_module --with-http_gzip_static_module --with-http_mp4_module --with-http_random_index_module --with-http_realip_module --with-http_secure_link_module --with-http_slice_module --with-http_ssl_module --with-http_stub_status_module --with-http_sub_module --with-http_v2_module --with-mail --with-mail_ssl_module --with-stream --with-stream_realip_module --with-stream_ssl_module --with-stream_ssl_preread_module"


# Возможны и другие модули для которых требуется самостоятельная установка пакетов, например:
# --with-http_xslt_module=dynamic --with-http_image_filter_module=dynamic --with-http_geoip_module=dynamic
# --with-http_perl_module=dynamic

# ----------------------------------


# Загрузка, распаковка и установка пакетов
# ----------------------------------

eval "$pkglist | grep \" git \""
if ! [ "$?" -eq 0 ]
then
    eval "$apt install git" || exit 1
fi

wget "https://raw.githubusercontent.com/fullincome/scripts/master/nginx-gost/nginx_conf.patch" || exit 1
wget ${url}/src/${pcre_ver}.tar.gz && wget ${url}/src/${zlib_ver}.tar.gz || exit 1
for i in ${openssl_packages[@]}; do wget ${url}/bin/"${revision_openssl}"/$i || exit 1; done 
tar -xzvf $csp && tar -xzvf ${pcre_ver}.tar.gz && tar -xzvf ${zlib_ver}.tar.gz || exit 1
cmd=$install" lsb-cprocsp-kc2*"${pkgmsys}

cd ${csp%.tgz} && ./install.sh && eval "$cmd" && cd .. || exit 1
cd ${pcre_ver} && ./configure && make && make install && cd .. || exit 1
cd ${zlib_ver} && ./configure && make && make install && cd .. || exit 1
for i in ${openssl_packages[@]}; do 
    cmd=$install" "$i
    eval "$cmd" || exit 1
done

# ----------------------------------

# Установка nginx
# ----------------------------------

git clone https://github.com/nginx/nginx.git
cd nginx || exit 1
git checkout branches/$nginx_branch || exit 1
cd .. && git apply nginx_conf.patch || exit 1
cd nginx
cmd="./auto/configure${nginx_paths}${nginx_parametrs}${cc_ld_opt}"
eval $cmd && make && make install || exit 1

if ! [ -d /var/cache/nginx ]
then 
    mkdir /var/cache/nginx
fi

# ----------------------------------
