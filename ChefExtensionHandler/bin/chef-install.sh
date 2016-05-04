#!/bin/sh

# returns script dir
get_script_dir(){
  SCRIPT=$(readlink -f "$0")
  script_dir=`dirname $SCRIPT`
  echo "${script_dir}"
}
commands_script_path=$(get_script_dir)

chef_extension_root=$commands_script_path/../

# install azure chef extension gem
install_chef_extension_gem(){
 echo "[$(date)] Installing Azure Chef Extension gem"
 gem install "$1" --no-ri --no-rdoc

  if test $? -ne 0; then
    echo "[$(date)] Azure Chef Extension gem installation failed"
    exit 1
  else
    echo "[$(date)] Azure Chef Extension gem installation succeeded"
  fi
}

get_config_settings_file() {
  config_files_path="$chef_extension_root/config/*.settings"
  config_file_name=`ls $config_files_path 2>/dev/null | sort -V | tail -1`

  echo $config_file_name
}

get_chef_version() {
  config_file_name=$(get_config_settings_file)
  if [ -z "$config_file_name" ]; then
    echo "No config file found !!"
  else
    if cat $config_file_name 2>/dev/null | grep -q "bootstrap_version"; then
      chef_version=`sed ':a;N;$!ba;s/\n//g' $config_file_name | sed 's/.*bootstrap_version" *: *" *\(.*\)/\1/' 2>/dev/null | awk -F\" '{ print $1 }' | sed 's/[ \t]*$//'`
      echo $chef_version
    else
      echo ""
    fi
  fi
}

chef_install_from_script(){
    echo "Reading chef-client version from settings file"
    chef_version=$(get_chef_version &)
    if [ "$chef_version" = "No config file found !!" ]; then
      echo "Configuration error. Azure chef extension Settings file missing."
      exit 1
    elif [ -z "$chef_version" ]; then
      curl -L https://omnitruck.chef.io/install.sh | sudo bash
    else
      curl -L https://omnitruck.chef.io/install.sh | sudo bash -s -- -v $chef_version
    fi
}

########### Script starts from here ##################
auto_update_false=/etc/chef/.auto_update_false

if [ -f $auto_update_false ]; then
  echo "[$(date)] Not doing install, as auto update is false"
else
  chef_install_from_script

  export PATH=/opt/chef/bin/:/opt/chef/embedded/bin:$PATH

  # check if azure-chef-extension is installed
  azure_chef_extn_gem=`gem list azure-chef-extension | grep azure-chef-extension | awk '{print $1}'`

  if test "$azure_chef_extn_gem" = "azure-chef-extension" ; then
    echo "azure-chef-extension is already installed."
  else
    # install azure chef extension gem
    install_chef_extension_gem "$chef_extension_root/gems/*.gem"
  fi
fi
