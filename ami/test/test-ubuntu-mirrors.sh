#!/bin/bash
# Ubuntu ARM64 (ubuntu-ports) Mirror Testing Script
# Tests mirrors for Noble (24.04) ARM64 support, speed, and reliability
# Usage: ./test-ubuntu-mirrors.sh
# shellcheck disable=SC2064,SC2155
set -e

# Auto-detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  ARCH="arm64"
elif [ "$ARCH" = "x86_64" ]; then
  ARCH="amd64"
fi

# Auto-detect Ubuntu release
if [ -f /etc/os-release ]; then
  RELEASE=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2)
else
  RELEASE="noble"
fi

# Auto-detect region (if running on EC2)
REGION=$(ec2-metadata --availability-zone 2>/dev/null | cut -d' ' -f2 | sed 's/[a-z]$//' || echo "unknown")

# Test files with expected sizes
TEST_RELEASE="dists/${RELEASE}/Release"                                                  # ~250KB
TEST_PACKAGES="dists/${RELEASE}-updates/main/binary-${ARCH}/Packages.xz"                 # ~1.7MB
TEST_PACKAGE="pool/main/l/llvm-toolchain-19/libllvm19_19.1.1-1ubuntu1~24.04.2_arm64.deb" # ~27MB

# Expected minimum sizes (in bytes) to validate we got actual files not error pages
MIN_RELEASE_SIZE=50000    # Release file should be >50KB
MIN_PACKAGES_SIZE=1000000 # Packages.xz should be >1MB (actual is ~1.7MB)
MIN_PACKAGE_SIZE=20000000 # libllvm19 should be >20MB

# Mirrors to test
MIRRORS=(
  "http://ports.ubuntu.com/ubuntu-ports"
  "https://ports.ubuntu.com/ubuntu-ports"
  "http://mirror.coganng.com/ubuntu-ports"
  "http://mirror.sg.gs/ubuntu-ports"
  "http://mirror.0x.sg/ubuntu-ports"
  "https://mirror.0x.sg/ubuntu-ports"
  "http://mirror.nus.edu.sg/ubuntu-ports"
  "http://my.archive.ubuntu.com/ubuntu-ports"
  "http://jp.archive.ubuntu.com/ubuntu-ports"
  "http://kr.archive.ubuntu.com/ubuntu-ports"
  "http://tw.archive.ubuntu.com/ubuntu-ports"
  "http://hk.archive.ubuntu.com/ubuntu-ports"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Temp directory for downloads
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

echo "=========================================="
echo "Ubuntu ARM64 Mirror Testing"
echo "=========================================="
echo "Test Date: $(date)"
echo "Region: ${REGION}"
echo "Release: ${RELEASE} (${ARCH})"
echo "Temp Dir: ${TEMP_DIR}"
echo ""

# Results array
declare -A MIRROR_RESULTS
declare -A MIRROR_SPEEDS

test_mirror() {
  local mirror="$1"
  local mirror_host=$(echo "$mirror" | sed 's|http[s]*://||' | cut -d'/' -f1)

  echo -e "${BLUE}Testing: ${mirror}${NC}"
  echo "----------------------------------------"

  # Extract score components
  local availability=0
  local dns_time=0
  local ping_time=999999
  local ttfb=999999
  local download_speed=0
  local total_score=0

  # Test 1: DNS Resolution
  echo -n "  [1/7] DNS resolution: "
  if dns_result=$(dig +time=2 +tries=1 "$mirror_host" 2>/dev/null | grep "Query time:" | awk '{print $4}'); then
    if [ -n "$dns_result" ]; then
      dns_time=$dns_result
      echo -e "${GREEN}${dns_time}ms${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      MIRROR_RESULTS["$mirror"]="DNS_FAIL"
      return
    fi
  else
    echo -e "${RED}FAIL${NC}"
    MIRROR_RESULTS["$mirror"]="DNS_FAIL"
    return
  fi

  # Test 2: Network Latency (ping)
  echo -n "  [2/7] Network latency: "
  if ping_result=$(ping -c 3 -W 2 "$mirror_host" 2>/dev/null | tail -1 | awk -F'/' '{print $5}'); then
    if [ -n "$ping_result" ] && [ "$ping_result" != "" ]; then
      ping_time=$ping_result
      echo -e "${GREEN}${ping_time}ms${NC}"
    else
      echo -e "${YELLOW}No response${NC}"
    fi
  else
    echo -e "${YELLOW}No ICMP${NC}"
  fi

  # Test 3: Check Release file exists and is valid
  echo -n "  [3/7] Release file: "
  local release_file="${TEMP_DIR}/Release_${mirror_host}"
  if curl -s -f --connect-timeout 5 --max-time 10 -o "$release_file" "${mirror}/${TEST_RELEASE}" 2>/dev/null; then
    local release_size=$(stat -f%z "$release_file" 2>/dev/null || stat -c%s "$release_file" 2>/dev/null)
    if [ "$release_size" -ge "$MIN_RELEASE_SIZE" ]; then
      # Validate it's actually a Release file
      if grep -q "^Suite: ${RELEASE}" "$release_file" 2>/dev/null; then
        echo -e "${GREEN}✓ Valid (${release_size} bytes)${NC}"
        availability=$((availability + 1))
      else
        echo -e "${RED}✗ Invalid content${NC}"
        MIRROR_RESULTS["$mirror"]="INVALID_CONTENT"
        return
      fi
    else
      echo -e "${RED}✗ Too small (${release_size} bytes, expected >${MIN_RELEASE_SIZE})${NC}"
      MIRROR_RESULTS["$mirror"]="ERROR_PAGE"
      return
    fi
  else
    echo -e "${RED}✗ Not found${NC}"
    MIRROR_RESULTS["$mirror"]="NOT_FOUND"
    return
  fi

  # Test 4: Check Packages.xz exists and is valid
  echo -n "  [4/7] Packages index: "
  local packages_file="${TEMP_DIR}/Packages_${mirror_host}.xz"
  if curl -s -f --connect-timeout 5 --max-time 15 -o "$packages_file" "${mirror}/${TEST_PACKAGES}" 2>/dev/null; then
    local packages_size=$(stat -f%z "$packages_file" 2>/dev/null || stat -c%s "$packages_file" 2>/dev/null)
    if [ "$packages_size" -ge "$MIN_PACKAGES_SIZE" ]; then
      # Validate it's actually an xz compressed file
      if file "$packages_file" | grep -q "XZ compressed data" 2>/dev/null; then
        echo -e "${GREEN}✓ Valid (${packages_size} bytes)${NC}"
        availability=$((availability + 1))
      else
        echo -e "${RED}✗ Not XZ compressed${NC}"
        MIRROR_RESULTS["$mirror"]="INVALID_FORMAT"
        return
      fi
    else
      echo -e "${RED}✗ Too small (${packages_size} bytes, expected >${MIN_PACKAGES_SIZE})${NC}"
      MIRROR_RESULTS["$mirror"]="ERROR_PAGE"
      return
    fi
  else
    echo -e "${RED}✗ Not found${NC}"
    MIRROR_RESULTS["$mirror"]="NOT_FOUND"
    return
  fi

  # Test 5: Time to First Byte (TTFB)
  echo -n "  [5/7] Connection time (TTFB): "
  if ttfb_result=$(curl -s -o /dev/null -w "%{time_starttransfer}" \
    --connect-timeout 5 --max-time 10 "${mirror}/${TEST_RELEASE}" 2>/dev/null); then
    if [ -n "$ttfb_result" ] && [ "$ttfb_result" != "0.000000" ]; then
      ttfb=$ttfb_result
      echo -e "${GREEN}${ttfb}s${NC}"
    else
      echo -e "${RED}FAIL${NC}"
      MIRROR_RESULTS["$mirror"]="TTFB_FAIL"
      return
    fi
  else
    echo -e "${RED}FAIL${NC}"
    MIRROR_RESULTS["$mirror"]="TTFB_FAIL"
    return
  fi

  # Test 6: Download Speed Test (actual package - 27MB)
  echo -n "  [6/7] Download speed (27MB package): "
  local package_file="${TEMP_DIR}/package_${mirror_host}.deb"
  local start_time=$(date +%s.%N)

  if curl -s -f --connect-timeout 10 --max-time 60 -o "$package_file" "${mirror}/${TEST_PACKAGE}" 2>/dev/null; then
    local end_time=$(date +%s.%N)
    local download_time=$(echo "$end_time - $start_time" | bc)
    local package_size=$(stat -f%z "$package_file" 2>/dev/null || stat -c%s "$package_file" 2>/dev/null)

    if [ "$package_size" -ge "$MIN_PACKAGE_SIZE" ]; then
      # Calculate speed in MB/s
      download_speed=$(echo "scale=2; $package_size / $download_time / 1024 / 1024" | bc)
      echo -e "${GREEN}${download_speed} MB/s (${download_time}s)${NC}"
      availability=$((availability + 1))
    else
      echo -e "${RED}✗ Invalid size (${package_size} bytes, expected >${MIN_PACKAGE_SIZE})${NC}"
      MIRROR_RESULTS["$mirror"]="INVALID_PACKAGE"
      return
    fi
  else
    echo -e "${RED}✗ FAIL/TIMEOUT${NC}"
    MIRROR_RESULTS["$mirror"]="DOWNLOAD_FAIL"
    return
  fi

  # Test 7: Validate package is actually a .deb
  echo -n "  [7/7] Package validation: "
  if file "$package_file" | grep -q "Debian binary package" 2>/dev/null; then
    echo -e "${GREEN}✓ Valid .deb${NC}"
  else
    echo -e "${RED}✗ Not a valid .deb${NC}"
    MIRROR_RESULTS["$mirror"]="INVALID_DEB"
    return
  fi

  # Calculate composite score
  # Lower is better: weighted sum of latency metrics and inverse of speed
  # Score = (ping_ms * 0.1) + (ttfb_s * 10) + (1000 / speed_mbps)
  local speed_component=$(echo "scale=2; 1000 / $download_speed" | bc)
  local ping_component=$(echo "scale=2; $ping_time * 0.1" | bc)
  local ttfb_component=$(echo "scale=2; $ttfb * 10" | bc)
  total_score=$(echo "scale=2; $ping_component + $ttfb_component + $speed_component" | bc)

  MIRROR_RESULTS["$mirror"]="PASS"
  MIRROR_SPEEDS["$mirror"]="$download_speed|$ping_time|$ttfb|$total_score"

  echo -e "  ${GREEN}✓ PASS${NC} - Score: ${total_score} (lower is better)"
  echo ""
}

# Test all mirrors
for mirror in "${MIRRORS[@]}"; do
  test_mirror "$mirror"
done

# Print summary
echo "=========================================="
echo "SUMMARY - Ranked by Performance Score"
echo "=========================================="
echo ""

# Sort by score and display
{
  for mirror in "${!MIRROR_SPEEDS[@]}"; do
    IFS='|' read -r speed ping ttfb score <<<"${MIRROR_SPEEDS[$mirror]}"
    printf "%s|%s|%s|%s|%s\n" "$score" "$speed" "$ping" "$ttfb" "$mirror"
  done
} | sort -t'|' -k1 -n | while IFS='|' read -r score speed ping ttfb mirror; do
  printf "${GREEN}✓${NC} %-50s Speed: %7s MB/s  Ping: %7s ms  TTFB: %6s s  Score: %s\n" \
    "$mirror" "$speed" "$ping" "$ttfb" "$score"
done

echo ""
echo "Failed mirrors:"
for mirror in "${!MIRROR_RESULTS[@]}"; do
  if [ "${MIRROR_RESULTS[$mirror]}" != "PASS" ]; then
    printf "${RED}✗${NC} %-50s ${RED}%s${NC}\n" "$mirror" "${MIRROR_RESULTS[$mirror]}"
  fi
done

echo ""
echo "=========================================="
echo "Test completed: $(date)"
echo "=========================================="
