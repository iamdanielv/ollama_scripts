#!/bin/bash
export C_RED='\e[31m'
export C_GREEN='\e[32m'
export C_YELLOW='\e[33m'
export C_BLUE='\e[34m'
export C_MAGENTA='\e[35m'
export C_CYAN='\e[36m'
export C_WHITE='\e[37m'
export C_GRAY='\e[30;1m'
export C_L_RED='\e[31;1m'
export C_L_GREEN='\e[32;1m'
export C_L_YELLOW='\e[33;1m'
export C_L_BLUE='\e[34;1m'
export C_L_MAGENTA='\e[35;1m'
export C_L_CYAN='\e[36;1m'
export C_L_WHITE='\e[37;1m'

export T_RESET='\e[0m'
export T_BOLD='\e[1m'
export T_ULINE='\e[4m'

export T_ERR="${T_BOLD}\e[31;1m"
export T_ERR_ICON="[${T_BOLD}${C_RED}✗${T_RESET}]"

export T_OK_ICON="[${T_BOLD}${C_GREEN}✓${T_RESET}]"
export T_INFO_ICON="[${T_BOLD}${C_YELLOW}i${T_RESET}]"
export T_QST_ICON="${T_BOLD}[?]${T_RESET}"

export DIV="-------------------------------------------------------------------------------"

function printMsg() {
  echo -e "${1}"
}

function printMsgNoNewline() {
  echo -n -e "${1}"
}

function printDatedMsgNoNewLine() {
  echo -n -e "$(getPrettyDate) ${1}"
}

function printErrMsg() {
  printMsg "${T_ERR_ICON}${T_ERR} ${1} ${T_RESET}"
}

function printOkMsg() {
  printMsg "${T_OK_ICON} ${1}${T_RESET}"
}

function getFormattedDate() {
  date +"%Y-%m-%d %I:%M:%S"
}

function getPrettyDate() {
  echo "${C_BLUE}$(getFormattedDate)${T_RESET}"
}

function printBanner() {
  printMsg "${C_BLUE}${DIV}"
  printMsg " ${1}"
  printMsg "${DIV}${T_RESET}"
}
