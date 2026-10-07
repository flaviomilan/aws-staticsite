#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

zone = json.loads(Path(sys.argv[1]).read_text())
subprocess.run([sys.executable, str(Path(__file__).with_name("check_dns.py")),
                "--domain", zone["HostedZone"]["Name"].rstrip("."), "--nameservers",
                *zone["DelegationSet"]["NameServers"]], check=True)
