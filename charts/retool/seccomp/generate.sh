#!/usr/bin/env bash
#
# Generates nsjail-seccomp.json and gvisor-seccomp.json from the upstream
# Docker default seccomp profile plus Retool-specific additions.
#
# Usage:
#   ./generate.sh           # fetch upstream + generate both profiles
#   ./generate.sh --check   # generate to temp dir + diff against checked-in files
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../files"

# ---------------------------------------------------------------------------
# Upstream Docker default seccomp profile pin
# ---------------------------------------------------------------------------
UPSTREAM_REPO="moby/profiles"
UPSTREAM_COMMIT="61eaf32614c7c71b60bd8927d3e6a4ffc8ff1f31"
UPSTREAM_URL="https://raw.githubusercontent.com/${UPSTREAM_REPO}/${UPSTREAM_COMMIT}/seccomp/default.json"

CACHE_FILE="${SCRIPT_DIR}/.docker-default-seccomp.json"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
check_deps() {
  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "ERROR: $cmd is required but not installed." >&2
      exit 1
    fi
  done
  local jq_version
  jq_version="$(jq --version 2>&1 | sed 's/jq-//')"
  if [[ "$(printf '%s\n' "1.6" "$jq_version" | sort -V | head -n1)" != "1.6" ]]; then
    echo "ERROR: jq >= 1.6 required (found $jq_version)" >&2
    exit 1
  fi
}

fetch_upstream() {
  if [[ ! -f "$CACHE_FILE" ]]; then
    echo "Fetching Docker default seccomp profile from ${UPSTREAM_REPO}@${UPSTREAM_COMMIT:0:12}..." >&2
    curl -fsSL "$UPSTREAM_URL" -o "$CACHE_FILE"
  else
    echo "Using cached Docker default: ${CACHE_FILE}" >&2
  fi
}

# ---------------------------------------------------------------------------
# nsjail profile
# ---------------------------------------------------------------------------
# Strategy: take Docker default verbatim, insert one unconditional ALLOW rule
# for the syscalls nsjail needs (clone, clone2, mount, pivot_root, sethostname,
# umount2). These overlap with CAP_SYS_ADMIN-gated rules already in the
# default; the unconditional rule ensures they are allowed even without that
# capability.
# ---------------------------------------------------------------------------
generate_nsjail() {
  local dest="$1"
  echo "Generating nsjail-seccomp.json..." >&2

  local retool_rule
  retool_rule="$(cat <<'RULE'
{
  "names": ["clone", "clone2", "mount", "pivot_root", "sethostname", "umount2"],
  "action": "SCMP_ACT_ALLOW",
  "comment": "Retool specific syscalls to enable nsjail sandboxing"
}
RULE
)"

  jq --argjson retool "$retool_rule" '
    # Insert the Retool rule right before the first CAP_SYS_ADMIN-gated rule
    (.syscalls | to_entries
      | map(select(.value.includes.caps // [] | index("CAP_SYS_ADMIN")))
      | .[0].key) as $idx |
    .syscalls = .syscalls[:$idx] + [$retool] + .syscalls[$idx:]
  ' "$CACHE_FILE" > "$dest"
}

# ---------------------------------------------------------------------------
# gVisor profile
# ---------------------------------------------------------------------------
# Strategy: flatten Docker default for x86_64 + aarch64 into one unconditional
# ALLOW list (dropping arg-based restrictions and capability gates), change
# defaultErrnoRet to ENOSYS (38), then add labelled rule groups for the
# syscalls gVisor/pasta need beyond the Docker default.
# ---------------------------------------------------------------------------
generate_gvisor() {
  local dest="$1"
  echo "Generating gvisor-seccomp.json..." >&2

  jq '
    # Architectures relevant to our archMap (x86_64 + aarch64)
    def relevant_arch:
      . as $a | ["amd64","x32","x86","arm","arm64"] | any(. == $a);

    # 1. Collect every syscall name from every ALLOW rule whose arch
    #    filter (if any) includes an x86_64- or aarch64-related arch.
    [.syscalls[] |
      select(.action == "SCMP_ACT_ALLOW") |
      select(
        (.includes.arches // null) == null or
        ([.includes.arches[] | select(relevant_arch)] | length > 0)
      ) |
      .names[]
    ] | unique as $docker_allow |

    # 2. Syscalls that belong in separate gVisor-specific rule groups
    ["clone","clone3","mount","pivot_root","ptrace","setns",
     "sethostname","umount2","unshare"] as $gvisor_groups |

    # 3. Main allowlist = Docker default (flattened) + io_uring - gVisor groups
    ($docker_allow - $gvisor_groups +
     ["io_uring_enter","io_uring_register","io_uring_setup"]
    | unique | sort) as $main |

    # 4. Build the profile
    {
      comment: "Docker default seccomp profile extended with syscalls required by gVisor runsc (systrap platform, rootless mode). Use with: docker run --security-opt seccomp=gvisor-seccomp.json",
      defaultAction: "SCMP_ACT_ERRNO",
      defaultErrnoRet: 38,
      archMap: [
        {architecture: "SCMP_ARCH_X86_64", subArchitectures: ["SCMP_ARCH_X86","SCMP_ARCH_X32"]},
        {architecture: "SCMP_ARCH_AARCH64", subArchitectures: []}
      ],
      syscalls: [
        {
          comment: ("Docker default allowlist (" + $ARGS.named.upstream_commit[0:12] + ", x86_64 + aarch64)"),
          names: $main,
          action: "SCMP_ACT_ALLOW"
        },
        {
          comment: "gVisor + pasta: namespace creation and entry (clone/unshare with CLONE_NEW* flags, setns to join namespaces)",
          names: ["clone","clone3","unshare","setns"],
          action: "SCMP_ACT_ALLOW"
        },
        {
          comment: "pasta: set hostname inside namespace (cosmetic, avoids warning)",
          names: ["sethostname"],
          action: "SCMP_ACT_ALLOW"
        },
        {
          comment: "gVisor: sandbox filesystem setup (tmpfs, proc, bind mounts)",
          names: ["mount","umount2"],
          action: "SCMP_ACT_ALLOW"
        },
        {
          comment: "gVisor: filesystem root isolation for sentry and gofer",
          names: ["pivot_root"],
          action: "SCMP_ACT_ALLOW"
        },
        {
          comment: "gVisor systrap platform: workload executor thread initialization",
          names: ["ptrace"],
          action: "SCMP_ACT_ALLOW"
        }
      ]
    }
  ' --arg upstream_commit "$UPSTREAM_COMMIT" "$CACHE_FILE" > "$dest"
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
check_deps
fetch_upstream

if [[ "${1:-}" == "--check" ]]; then
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  generate_nsjail "${tmpdir}/nsjail-seccomp.json"
  generate_gvisor "${tmpdir}/gvisor-seccomp.json"

  rc=0
  for f in nsjail-seccomp.json gvisor-seccomp.json; do
    if ! diff -u "${OUTPUT_DIR}/${f}" "${tmpdir}/${f}"; then
      echo "MISMATCH: ${f} is out of date. Run charts/retool/seccomp/generate.sh to regenerate." >&2
      rc=1
    else
      echo "OK: ${f} is up to date." >&2
    fi
  done
  exit "$rc"
else
  generate_nsjail "${OUTPUT_DIR}/nsjail-seccomp.json"
  generate_gvisor "${OUTPUT_DIR}/gvisor-seccomp.json"
  echo "Done. Profiles written to ${OUTPUT_DIR}/" >&2
fi
