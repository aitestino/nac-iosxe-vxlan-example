[![Terraform Version](https://img.shields.io/badge/terraform-%5E1.8-blue)](https://www.terraform.io)
[![NaC IOS-XE](https://img.shields.io/badge/NaC-IOS--XE-00bceb)](https://netascode.cisco.com)
[![License](https://img.shields.io/badge/license-Apache%202.0-lightgrey)](LICENSE)

# EVPN-VXLAN Fabric — Network-as-Code Template-Driven Example

A scalable, **template-driven EVPN-VXLAN fabric** defined entirely as YAML data and deployed via [Network-as-Code (NaC)](https://netascode.cisco.com) with Terraform. This repository demonstrates how to manage a Cisco Catalyst 9000 EVPN-VXLAN fabric using **composable templates and variables** — devices are inventory entries, and templates auto-generate the full configuration.

> **Companion Repository:** For a per-device, explicit YAML approach to the same fabric design, see [`nac-iosxe-campus-evpn-vxlan-example`](https://github.com/netascode/nac-iosxe-campus-evpn-vxlan-example). That repository spells out every device's configuration in full for maximum readability and learning. This one focuses on scalability and DRY operations.

---

## Table of Contents

- [Overview](#overview)
- [Design Approach: Template-Driven vs Per-Device](#design-approach-template-driven-vs-per-device)
- [Topology](#topology)
  - [Physical Topology Diagram](#physical-topology-diagram)
  - [Underlay Topology (OSPF + PIM)](#underlay-topology-ospf--pim)
  - [Overlay Topology (iBGP EVPN)](#overlay-topology-ibgp-evpn)
  - [Device Inventory](#device-inventory)
  - [Device Roles](#device-roles)
- [Architecture Deep Dive](#architecture-deep-dive)
  - [Underlay Network (OSPF)](#underlay-network-ospf)
  - [Underlay Multicast (PIM + Anycast RP + MSDP)](#underlay-multicast-pim--anycast-rp--msdp)
  - [Overlay Network (BGP EVPN)](#overlay-network-bgp-evpn)
  - [VXLAN Data Plane](#vxlan-data-plane)
  - [VRF and Tenant Design](#vrf-and-tenant-design)
  - [Anycast Gateway](#anycast-gateway)
- [IP Addressing Scheme](#ip-addressing-scheme)
  - [Loopback Addresses](#loopback-addresses)
  - [Point-to-Point Underlay Links](#point-to-point-underlay-links)
  - [Tenant Subnets](#tenant-subnets)
- [VXLAN and VNI Mapping](#vxlan-and-vni-mapping)
  - [VNI Numbering Convention](#vni-numbering-convention)
- [BGP Design](#bgp-design)
  - [iBGP Fabric Peering (AS 65000)](#ibgp-fabric-peering-as-65000)
  - [L2VPN EVPN Address Family](#l2vpn-evpn-address-family)
  - [Per-VRF IPv4/IPv6 Address Family](#per-vrf-ipv4ipv6-address-family)
- [Per-Device Feature Matrix](#per-device-feature-matrix)
- [Template System](#template-system)
  - [How Templates Work](#how-templates-work)
  - [Template Inventory](#template-inventory)
  - [Interface Groups](#interface-groups)
  - [Variables and Scope](#variables-and-scope)
  - [Template Rendering Flow](#template-rendering-flow)
  - [Adding a New Leaf (Walkthrough)](#adding-a-new-leaf-walkthrough)
  - [Adding a New L2 Service (Walkthrough)](#adding-a-new-l2-service-walkthrough)
  - [Adding a New L3 Service (Walkthrough)](#adding-a-new-l3-service-walkthrough)
- [YAML-to-CLI Rendering Examples](#yaml-to-cli-rendering-examples)
- [Repository Structure](#repository-structure)
  - [Data Files](#data-files)
  - [Template Files](#template-files)
  - [Supporting Files](#supporting-files)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [1. Clone the Repository](#1-clone-the-repository)
  - [2. Set Credentials](#2-set-credentials)
  - [3. Initialize Terraform](#3-initialize-terraform)
  - [4. Plan and Apply](#4-plan-and-apply)
  - [5. Destroy (Cleanup)](#5-destroy-cleanup)
- [Verification Commands](#verification-commands)
- [Configuration Patterns Demonstrated](#configuration-patterns-demonstrated)
- [Best Practices](#best-practices)
- [Documentation](#documentation)

---

## Overview

This example deploys a **4-device EVPN-VXLAN fabric** using a template-driven approach with the following characteristics:

| Attribute | Value |
|---|---|
| **Fabric Type** | EVPN-VXLAN with BGP control plane |
| **Device Count** | 4 (2 spines, 2 leaf VTEPs) |
| **Platform** | Cisco Catalyst 9000 series |
| **Underlay Routing** | OSPF Process 1, Area 0 (single area) |
| **Underlay Links** | IP unnumbered to Loopback 0 |
| **Underlay Multicast** | PIM Sparse-Mode, SSM, Anycast RP, MSDP |
| **Overlay Routing** | iBGP with L2VPN EVPN address family (route-reflector) |
| **BGP AS** | 65000 |
| **Tenants** | 2 VRFs (`BLUE`, `GREEN`) with 2 L2 services (VLANs 101, 102) |
| **Encapsulation** | VXLAN with multicast + ingress replication |
| **System MTU** | 8978 bytes (jumbo frames for VXLAN overhead) |
| **Design** | Template-driven — devices defined by variables, templates auto-generate config |

The key differentiator of this repository is its **template-driven architecture**: instead of writing 200+ lines of YAML per device, each device is defined by a handful of variables (hostname, loopback IP, VTEP IP) and templates auto-wire everything — BGP neighbors, OSPF interfaces, NVE tunnels, EVPN instances, and VRFs.

---

## Design Approach: Template-Driven vs Per-Device

The NaC IOS-XE module supports two fundamentally different ways to define a fabric. This repository uses **template-driven composable services** where devices are defined by variables and templates auto-generate the full configuration. The NetAsCode organization also publishes [`nac-iosxe-campus-evpn-vxlan-example`](https://github.com/netascode/nac-iosxe-campus-evpn-vxlan-example), which takes the opposite approach: **per-device explicit YAML** where every device has its own self-contained file with every interface, neighbor, and VNI spelled out.

Both are valid. They serve different audiences and operational models:

| | This Repository (Template-Driven) | [`nac-iosxe-campus-evpn-vxlan-example`](https://github.com/netascode/nac-iosxe-campus-evpn-vxlan-example) (Per-Device) |
|---|---|---|
| **Philosophy** | Devices are inventory entries; templates generate config | Every device is a complete, readable document |
| **Adding a new leaf** | Add one inventory entry with a few variables — templates auto-wire everything | Write ~220 lines of YAML, update BGP neighbors on every other device |
| **Adding a new L2 service** | Create one 10-line service YAML file | Edit 4 device files (every VTEP) |
| **Adding a new L3 service** | Create one 13-line service YAML file | Edit 4 device files (VRF, VLANs, SVIs, NVE, EVPN, BGP) |
| **Readability** | Must follow template references to understand what a device actually does | Open any file and see the entire device config — no template chasing |
| **Configuration drift** | Unlikely — shared variables and templates enforce consistency | Possible — each device is independent, values can diverge silently |
| **Learning curve** | Higher — requires understanding NaC template system, variables, device groups | Low — standard YAML, maps directly to IOS-XE CLI |
| **Auditability** | Requires rendering templates to see effective config | Excellent — every value is visible in one place per device |
| **Scale** | Scales to hundreds of devices with minimal YAML growth | Manageable for 4-10 devices; becomes unwieldy beyond that |
| **Use case** | Production fabrics, multi-site deployments, Day 2 operations at scale | Reference architecture, learning, small/lab fabrics, migration from CLI |

**When to use this repo's approach:**
- You're building a production fabric that will grow beyond 10 devices
- You need Day 2 service provisioning where adding VLANs/VRFs should be a single-file operation
- You want to enforce consistency — shared templates mean all leaves get identical base config
- You have multiple sites with similar topologies and want to reuse templates across them

**When to use the per-device approach:**
- You want to study exactly what a Campus EVPN-VXLAN fabric looks like in the NaC data model
- You're migrating from CLI/templates and want to see the 1:1 mapping between YAML and IOS-XE
- You have a small fabric (< 10 devices) where per-device clarity is more valuable than DRY
- You need full control over every device and don't want template abstractions hiding details

> **Recommendation:** Start with [`nac-iosxe-campus-evpn-vxlan-example`](https://github.com/netascode/nac-iosxe-campus-evpn-vxlan-example) to understand the data model and what a complete EVPN-VXLAN fabric looks like. Then move to this repository when you're ready for a scalable, template-driven operational model.

---

## Topology

### Physical Topology Diagram

```
                ┌──────────┐           ┌──────────┐
                │  SPINE1  │           │  SPINE2  │
                │ Lo0: .1  │───────────│ Lo0: .2  │
                │Lo100: RP │   MSDP    │Lo100: RP │
                │ Anycast  │   Peer    │ Anycast  │
                │10.1.101.1│           │10.1.101.1│
                └─┬──────┬─┘           └─┬──────┬─┘
                  │      │               │      │
         ┌────────┘      └───────┬───────┘      └────────┐
         │                       │                        │
    ┌────┴─────┐                 │                 ┌──────┴───┐
    │  LEAF1   │                 │                 │  LEAF2   │
    │ (VTEP)   │                 │                 │ (VTEP)   │
    │ Lo0: .3  │                 │                 │ Lo0: .4  │
    │ Lo1: VTEP│         (iBGP EVPN via           │ Lo1: VTEP│
    │10.1.200.1│          route-reflector)         │10.1.200.2│
    └──────────┘                                   └──────────┘

    Legend:
      .X   = Loopback0 last octet (10.1.100.X/32) — OSPF/BGP RID
      Lo1  = Dedicated VTEP loopback (10.1.200.X/32) — NVE source
      Lo100= Anycast RP (10.1.101.1/32) — shared on both spines
      ───  = OSPF P2P + PIM sparse-mode underlay links (IP unnumbered)
```

### Underlay Topology (OSPF + PIM)

All 4 devices participate in OSPF Process 1, Area 0 with PIM sparse-mode on every fabric interface. The spines provide Anycast RP via a shared Loopback 100 address, synchronized through MSDP:

```
            IP Unnumbered (Lo0)
  SPINE1 ──────────────────── SPINE2
  [Lo100: Anycast RP]  MSDP  [Lo100: Anycast RP]
  10.1.101.1  ←──── peer ────→ 10.1.101.1
    │ ╲                          ╱ │
    │  GigabitEthernet1/0/1     │  │
    │   ╲                  ╱    │  │
    │    LEAF1            ╱     │  │
    │    │                │     │  │
    │  GigabitEthernet1/0/2     │  │
    │             ╲        ╱    │  │
    │              LEAF2        │  │
    │                           │  │
    └── All links: OSPF P2P + PIM sparse-mode
        All links: IP unnumbered to Loopback 0
        All devices: pim.rp_address → 10.1.101.1
```

### Overlay Topology (iBGP EVPN)

The overlay uses a **route-reflector** design — spines are iBGP route-reflectors, leaves peer only with spines (not with each other):

```
    SPINE1 ─────────────── SPINE2
   (10.1.100.1)           (10.1.100.2)
   Route-Reflector         Route-Reflector
      │  ╲              ╱  │
      │   ╲            ╱   │
      │    ╲          ╱    │
      │     ╲        ╱     │
      │      ╲      ╱      │
      │       ╲    ╱       │
    LEAF1                LEAF2
   (10.1.100.3)         (10.1.100.4)
   VTEP: 10.1.200.1     VTEP: 10.1.200.2

   iBGP (AS 65000)
   L2VPN EVPN address family
   Spines: route-reflector-client for leaves
   Update-source: Loopback 0
   NVE source: Loopback 1 (dedicated VTEP IP)
   Send-community: both
```

### Device Inventory

| Hostname | Role | Loopback 0 (RID) | Loopback 1 (VTEP) | Loopback 100 (RP) | Mgmt IP | BGP AS |
|---|---|---|---|---|---|---|
| `SPINE1` | Spine / Route-Reflector 1 | 10.1.100.1/32 | — | 10.1.101.1/32 | 10.1.1.3 | 65000 |
| `SPINE2` | Spine / Route-Reflector 2 | 10.1.100.2/32 | — | 10.1.101.1/32 | 10.1.1.4 | 65000 |
| `LEAF1` | Leaf VTEP 1 | 10.1.100.3/32 | 10.1.200.1/32 | — | 10.1.1.1 | 65000 |
| `LEAF2` | Leaf VTEP 2 | 10.1.100.4/32 | 10.1.200.2/32 | — | 10.1.1.2 | 65000 |

> **Loopback Design:** Loopback 0 is the routing identity (OSPF RID, BGP router-id). Loopback 1 is the dedicated VTEP identity on leaves (NVE source, EVPN router-id). Loopback 100 is the Anycast RP address, shared between both spines and synchronized via MSDP.

### Device Roles

#### Spine Route-Reflectors (`SPINE1`, `SPINE2`)

These devices serve a **dual role** in this fabric:

1. **Spine / Route-Reflector**: They act as iBGP route-reflectors for the L2VPN EVPN address family, so leaves only need to peer with spines rather than forming a full mesh.
2. **Anycast RP**: Both spines share Loopback 100 (`10.1.101.1`) as the PIM RP, with MSDP peering between them to synchronize multicast source information.

Key characteristics:
- iBGP L2VPN EVPN peering with all leaves (`route-reflector-client`)
- OSPF underlay on all fabric interfaces
- PIM sparse-mode on all fabric interfaces + Anycast RP (Loopback 100)
- MSDP peering with the other spine for RP redundancy
- No VTEP/NVE/EVPN configuration (pure control-plane role)
- No Loopback 1 (no VTEP identity needed)

#### Leaf VTEPs (`LEAF1`, `LEAF2`)

These are the **edge devices** where hosts and services attach:

- Full EVPN+VXLAN configuration with NVE interface sourced from **Loopback 1**
- iBGP EVPN peering with both spines (via Loopback 0)
- L2 and L3 services deployed via service templates (L2 VNIs, VRFs, SVIs)
- EVPN instance auto-configuration via templates
- PIM sparse-mode on all fabric interfaces, RP pointing to spine Anycast RP

---

## Architecture Deep Dive

### Underlay Network (OSPF)

The underlay provides basic IP connectivity between all loopbacks using **OSPF Process 1, Area 0**:

- All point-to-point links use **IP unnumbered** to Loopback 0 — no per-link subnets required
- All interfaces use `network-type point-to-point` for fast convergence (no DR/BDR election)
- Loopback 0 on every device is advertised into OSPF
- Loopback 1 on leaves and Loopback 100 on spines are advertised into OSPF
- Interface groups (`fabric`, `loopback`) enforce consistent OSPF + PIM config across all interfaces

```
IOS-XE CLI equivalent (per fabric interface on a leaf):

  interface GigabitEthernet1/0/1
   no switchport
   ip address negotiated            ← IP unnumbered to Loopback 0
   ip ospf network point-to-point
   ip ospf 1 area 0
   ip pim sparse-mode

  interface Loopback0
   ip address 10.1.100.3 255.255.255.255
   ip ospf network point-to-point
   ip ospf 1 area 0
   ip pim sparse-mode
```

### Underlay Multicast (PIM + Anycast RP + MSDP)

VXLAN BUM (Broadcast, Unknown Unicast, Multicast) traffic requires a functioning multicast underlay. This fabric implements the full multicast stack:

**PIM Sparse-Mode** is enabled on every fabric-facing interface and loopback across all 4 devices via the `fabric` and `loopback` interface groups. This allows multicast Join/Prune messages to propagate and multicast distribution trees to form.

**PIM SSM (Source Specific Multicast)** is enabled globally on all devices via `ssm_default: true`, providing efficient source-based multicast for known source scenarios.

**Anycast RP** provides a redundant Rendezvous Point using a shared IP address (`10.1.101.1`) on Loopback 100 of both spines. From the perspective of every other device in the fabric, there is a single RP address — but two physical devices serve it.

**MSDP (Multicast Source Discovery Protocol)** synchronizes active multicast source information between the two spine RPs. Each spine peers with the other via Loopback 0:

```
IOS-XE CLI equivalent (spine):

  interface Loopback100
   description Anycast RP
   ip address 10.1.101.1 255.255.255.255
   ip ospf network point-to-point
   ip ospf 1 area 0
   ip pim sparse-mode

  ip pim ssm default
  ip pim rp-address 10.1.101.1

  ip msdp originator-id Loopback0
  ip msdp peer 10.1.100.2 connect-source Loopback0   ← on SPINE1
  ip msdp peer 10.1.100.1 connect-source Loopback0   ← on SPINE2
```

**Multicast flow for VXLAN BUM:**
```
  Host sends broadcast on VLAN 101 at LEAF1
    │
    ▼
  LEAF1 encapsulates in VXLAN, sends to mcast group 225.1.1.1
    │
    ▼
  PIM sparse-mode tree (rooted at RP 10.1.101.1) delivers
  the multicast to all VTEPs that have joined group 225.1.1.1
    │
    ▼
  LEAF2 receives and decapsulates
```

### Overlay Network (BGP EVPN)

The overlay uses **iBGP with L2VPN EVPN address family** within AS 65000:

- Spines are **route-reflectors** — leaves only peer with spines, not with each other
- BGP sessions are sourced from **Loopback 0** (routing identity, separate from VTEP)
- `no bgp default ipv4-unicast` — explicit per-AF neighbor activation
- **Send-community both** ensures extended communities (route targets) are propagated
- **Route-reflector-client** set on spines for each leaf neighbor in L2VPN EVPN
- Each leaf VTEP advertises:
  - **EVPN Type-2 routes**: MAC/IP bindings learned from local hosts
  - **EVPN Type-5 routes**: IP prefix routes for inter-subnet routing (via `advertise l2vpn evpn` in VRF)

```
IOS-XE CLI equivalent (leaf):

  router bgp 65000
   bgp router-id interface Loopback0
   bgp log-neighbor-changes
   no bgp default ipv4-unicast
   neighbor 10.1.100.1 remote-as 65000
   neighbor 10.1.100.1 update-source Loopback0
   neighbor 10.1.100.2 remote-as 65000
   neighbor 10.1.100.2 update-source Loopback0
   !
   address-family l2vpn evpn
    neighbor 10.1.100.1 activate
    neighbor 10.1.100.1 send-community both
    neighbor 10.1.100.2 activate
    neighbor 10.1.100.2 send-community both
   exit-address-family
```

```
IOS-XE CLI equivalent (spine — route-reflector):

  router bgp 65000
   bgp router-id interface Loopback0
   bgp log-neighbor-changes
   no bgp default ipv4-unicast
   neighbor 10.1.100.3 remote-as 65000
   neighbor 10.1.100.3 update-source Loopback0
   neighbor 10.1.100.4 remote-as 65000
   neighbor 10.1.100.4 update-source Loopback0
   !
   address-family l2vpn evpn
    neighbor 10.1.100.3 activate
    neighbor 10.1.100.3 send-community both
    neighbor 10.1.100.3 route-reflector-client
    neighbor 10.1.100.4 activate
    neighbor 10.1.100.4 send-community both
    neighbor 10.1.100.4 route-reflector-client
   exit-address-family
```

### VXLAN Data Plane

| Component | Value | Description |
|---|---|---|
| **NVE Interface** | `nve 1` | VXLAN Tunnel Endpoint interface |
| **Source Interface** | `Loopback 1` | Dedicated VTEP IP (separate from routing RID) |
| **Host Reachability** | BGP | Control-plane learning via EVPN |
| **Default GW Advertise** | Yes | Anycast gateway MAC in Type-2 routes |
| **Route Target** | Auto VNI | Automatic RT derivation from VNI values |
| **L3 VNI (BLUE)** | 201010 | Maps to VLAN 1010, VRF BLUE |
| **L3 VNI (GREEN)** | 201000 | Maps to VLAN 1000, VRF GREEN |
| **L2 VNI 10101** | Maps to VLAN 101 | L2 service segment |
| **L2 VNI 10102** | Maps to VLAN 102 | L2 service segment |
| **L2 BUM Replication** | Multicast | Groups: 225.1.1.1 (VLAN 101), 225.1.1.2 (VLAN 102) |
| **L3 BUM Replication** | Ingress | For VRF-associated VLANs |

```
IOS-XE CLI equivalent (leaf):

  l2vpn evpn
   replication-type static
   router-id Loopback1                  ← dedicated VTEP loopback
   default-gateway advertise
   logging peer state
   route-target auto vni

  interface nve1
   source-interface Loopback1           ← dedicated VTEP loopback
   host-reachability protocol bgp
   member vni 10101 mcast-group 225.1.1.1   ← L2 VNI (service 101)
   member vni 10102 mcast-group 225.1.1.2   ← L2 VNI (service 102)
   member vni 101001 ingress-replication     ← L2 VNI for VRF GREEN (VLAN 1001)
   member vni 101011 ingress-replication     ← L2 VNI for VRF BLUE (VLAN 1011)
   member vni 201000 vrf GREEN               ← L3 VNI (core)
   member vni 201010 vrf BLUE                ← L3 VNI (core)
```

### VRF and Tenant Design

Two VRFs are deployed as L3 services, each with its own core VLAN and associated tenant VLANs:

**VRF BLUE:**

| Attribute | Value |
|---|---|
| **VRF Name** | BLUE |
| **Route Distinguisher** | `65000:1010` |
| **Import/Export RT** | `65000:1010` |
| **Stitching Import/Export RT** | `65000:1010` |
| **Core VLAN** | 1010 (L3 VNI: 201010) |
| **Tenant VLANs** | 1011 |
| **IPv4/IPv6 AF** | `advertise l2vpn evpn`, redistribute connected + static |

**VRF GREEN:**

| Attribute | Value |
|---|---|
| **VRF Name** | GREEN |
| **Route Distinguisher** | `65000:1000` |
| **Import/Export RT** | `65000:1000` |
| **Stitching Import/Export RT** | `65000:1000` |
| **Core VLAN** | 1000 (L3 VNI: 201000) |
| **Tenant VLANs** | 1001 |
| **IPv4/IPv6 AF** | `advertise l2vpn evpn`, redistribute connected + static |

### Anycast Gateway

The L3 service template creates SVI interfaces on each VTEP with the same IP and VRF forwarding. Combined with `default_gateway_advertise: true` under `l2vpn evpn`, this provides seamless host mobility across the fabric:

| VLAN | Gateway IP | VRF | Devices |
|---|---|---|---|
| 1001 | 172.17.1.1/24 | GREEN | LEAF1, LEAF2 |
| 1011 | 172.17.1.1/24 | BLUE | LEAF1, LEAF2 |

The `default_gateway_advertise: true` setting under `l2vpn evpn` ensures the anycast gateway MAC is advertised in EVPN Type-2 routes, so all remote VTEPs know the distributed gateway exists.

---

## IP Addressing Scheme

### Loopback Addresses

| Device | Loopback 0 (RID) | Loopback 1 (VTEP) | Loopback 100 (RP) |
|---|---|---|---|
| `SPINE1` | 10.1.100.1/32 | — | 10.1.101.1/32 |
| `SPINE2` | 10.1.100.2/32 | — | 10.1.101.1/32 |
| `LEAF1` | 10.1.100.3/32 | 10.1.200.1/32 | — |
| `LEAF2` | 10.1.100.4/32 | 10.1.200.2/32 | — |

**Address block allocation:**
- `10.1.100.0/24` — Underlay routing identities (Loopback 0)
- `10.1.101.0/24` — Anycast RP (.1)
- `10.1.200.0/24` — VTEP identities (Loopback 1)

### Point-to-Point Underlay Links

All underlay links use **IP unnumbered** to Loopback 0 — no per-link /31 subnets are needed. This simplifies address planning significantly as the fabric scales:

| Link | Spine Interface | Leaf Interface | Notes |
|---|---|---|---|
| SPINE1 ↔ LEAF1 | Gi1/0/1 | Gi1/0/1 | Spine index 0 (LEAF1), Leaf index 0 (SPINE1) |
| SPINE1 ↔ LEAF2 | Gi1/0/2 | Gi1/0/1 | Spine index 1 (LEAF2), Leaf index 0 (SPINE1) |
| SPINE2 ↔ LEAF1 | Gi1/0/1 | Gi1/0/2 | Spine index 0 (LEAF1), Leaf index 1 (SPINE2) |
| SPINE2 ↔ LEAF2 | Gi1/0/2 | Gi1/0/2 | Spine index 1 (LEAF2), Leaf index 1 (SPINE2) |

> **Template auto-wiring:** The underlay leaf and spine templates iterate over the opposing role's device list and assign interface IDs automatically using the device index. Adding a LEAF3 to the LEAFS device group would automatically create Gi1/0/3 on both spines and Gi1/0/1 + Gi1/0/2 on LEAF3.

### Tenant Subnets

| Subnet | VLAN | VNI | VRF | Gateway IP | Purpose |
|---|---|---|---|---|---|
| 172.17.1.0/24 | 1001 | 101001 | GREEN | 172.17.1.1 | GREEN tenant subnet |
| 172.17.1.0/24 | 1011 | 101011 | BLUE | 172.17.1.1 | BLUE tenant subnet |

---

## VXLAN and VNI Mapping

| VLAN ID | VLAN Name | VNI | EVPN Instance | Type | Replication | Scope |
|---|---|---|---|---|---|---|
| 101 | L2_101 | 10101 | 101 | L2 VNI | Multicast (225.1.1.1) | All leaves |
| 102 | L2_102 | 10102 | 102 | L2 VNI | Multicast (225.1.1.2) | All leaves |
| 1000 | GREEN | 201000 | — | L3 VNI (VRF core) | — | All leaves |
| 1001 | GREEN_1001 | 101001 | 1001 | L2 VNI (VRF) | Ingress | All leaves |
| 1010 | BLUE | 201010 | — | L3 VNI (VRF core) | — | All leaves |
| 1011 | BLUE_1011 | 101011 | 1011 | L2 VNI (VRF) | Ingress | All leaves |

### VNI Numbering Convention

The templates use **string concatenation** (prefix + VLAN ID) rather than arithmetic:

| Component | Pattern | Template Expression | Example |
|---|---|---|---|
| **L2 VNI (Segment)** | `"10" + vlan_id` | `10${vlan_id}` | VNI 10101 → VLAN 101 |
| **L3 VNI (Core VLAN)** | `"20" + core_vlan_id` | `20${core_vlan_id}` | VNI 201010 → VLAN 1010 (BLUE) |
| **L2 VNI (VRF Tenant)** | `"10" + vlan_id` | `10${vlan.id}` | VNI 101011 → VLAN 1011 (BLUE) |
| **L2VPN EVPN Instance** | Matches VLAN ID | `${vlan_id}` | Instance 101 → VLAN 101 |

---

## BGP Design

### iBGP Fabric Peering (AS 65000)

The spines act as **route-reflectors** — leaves only peer with spines:

| Feature | Configuration |
|---|---|
| **AS Number** | 65000 |
| **Router ID** | Loopback 0 (per-device) |
| **Update Source** | Loopback 0 |
| **Address Families** | L2VPN EVPN |
| **Send Community** | Both (standard + extended) |
| **Default IPv4 Unicast** | No (explicit per-AF activation) |
| **Route-Reflector** | Spines set `route-reflector-client` on leaf neighbors |

**iBGP Peering Matrix:**

| Device | Peer 1 | Peer 2 | Role |
|---|---|---|---|
| `SPINE1` | LEAF1 (10.1.100.3) | LEAF2 (10.1.100.4) | Route-Reflector |
| `SPINE2` | LEAF1 (10.1.100.3) | LEAF2 (10.1.100.4) | Route-Reflector |
| `LEAF1` | SPINE1 (10.1.100.1) | SPINE2 (10.1.100.2) | Client |
| `LEAF2` | SPINE1 (10.1.100.1) | SPINE2 (10.1.100.2) | Client |

> **Route-reflector benefit:** In a full-mesh iBGP design (like the per-device example), adding a new leaf requires updating BGP neighbors on every existing device. With route-reflectors, adding a new leaf only requires peering with the two spines — the spines handle route distribution. The templates automate even this: add a device to the LEAFS group and the spine template auto-discovers it.

### L2VPN EVPN Address Family

On each EVPN speaker, the L2VPN EVPN address family is activated with:
- **activate**: true (enable the neighbor for EVPN routes)
- **send-community**: both (required for route target propagation)
- **route-reflector-client**: true (on spines only, for leaf neighbors)

### Per-VRF IPv4/IPv6 Address Family

Each VTEP configures IPv4 and IPv6 address families under each VRF with:
- **advertise l2vpn evpn**: Advertises EVPN routes into the VRF's routing table
- **redistribute connected**: Redistributes directly connected subnets (SVIs) into BGP
- **redistribute static**: Redistributes static routes into BGP

---

## Per-Device Feature Matrix

| Feature | SPINE1 | SPINE2 | LEAF1 | LEAF2 |
|---|:---:|:---:|:---:|:---:|
| OSPF Process 1 | ✓ | ✓ | ✓ | ✓ |
| PIM Sparse-Mode (all intf) | ✓ | ✓ | ✓ | ✓ |
| PIM SSM Default | ✓ | ✓ | ✓ | ✓ |
| PIM RP → 10.1.101.1 | ✓ | ✓ | ✓ | ✓ |
| Anycast RP (Loopback 100) | ✓ | ✓ | — | — |
| MSDP Peering | ✓ | ✓ | — | — |
| BGP AS 65000 | ✓ | ✓ | ✓ | ✓ |
| iBGP L2VPN EVPN | ✓ | ✓ | ✓ | ✓ |
| Route-Reflector | ✓ | ✓ | — | — |
| NVE (source: Lo1) | — | — | ✓ | ✓ |
| EVPN (router-id: Lo1) | — | — | ✓ | ✓ |
| Default GW Advertise | — | — | ✓ | ✓ |
| Route Target Auto VNI | — | — | ✓ | ✓ |
| VRF BLUE | — | — | ✓ | ✓ |
| VRF GREEN | — | — | ✓ | ✓ |
| EVPN Instances | — | — | ✓ | ✓ |
| Anycast GW SVIs | — | — | ✓ | ✓ |
| IP Routing | ✓ | ✓ | ✓ | ✓ |
| IPv6 Unicast Routing | ✓ | ✓ | ✓ | ✓ |
| IP Multicast Routing | ✓ | ✓ | ✓ | ✓ |
| System MTU 8978 | ✓ | ✓ | ✓ | ✓ |

---

## Template System

### How Templates Work

The NaC IOS-XE module supports **composable templates** that generate configuration from variables. Instead of writing explicit YAML for each device, you:

1. Define **devices** with a few variables (hostname, loopback IP, VTEP IP)
2. Assign devices to **device groups** that reference templates
3. Templates use variables and dynamic lookups to generate the full configuration

The module merges all template outputs with any explicit device configuration, producing a complete config per device.

### Template Inventory

| Template | Type | Applied To | Purpose |
|---|---|---|---|
| `global` | Model | All devices | Hostname, IP routing, IPv6, multicast, MTU, Loopback 0 |
| `underlay_fabric` | Model | All devices | OSPF process, BGP AS/router-id, PIM SSM + RP address |
| `underlay_leaf` | File | LEAFS group | Loopback 1, fabric interfaces, NVE, BGP neighbors→spines, EVPN config |
| `underlay_spine` | File | SPINES group | Loopback 100 (RP), fabric interfaces, MSDP, BGP neighbors→leaves (RR) |
| `service_l2` | File | Per-service groups | VLAN, EVPN instance, NVE VNI with multicast group |
| `service_l3` | File | Per-service groups | VRF, core VLAN, tenant VLANs, SVIs, NVE VNI, BGP VRF AF, EVPN instances |

### Interface Groups

Interface groups define reusable configuration profiles applied to interfaces by name reference:

| Group | Configuration | Applied To |
|---|---|---|
| `fabric` | `no switchport`, IP unnumbered Lo0, OSPF P2P area 0, PIM sparse-mode | All spine-leaf physical links |
| `loopback` | OSPF P2P area 0, PIM sparse-mode | All loopback interfaces |

```yaml
# interface_groups.nac.yaml
iosxe:
  interface_groups:
    - name: fabric
      configuration:
        switchport:
          enable: false
        ipv4:
          unnumbered_interface_type: Loopback
          unnumbered_interface_id: 0
        ospf:
          process_ids:
            - id: 1
              areas: ["0"]
          network_type: point-to-point
        pim:
          sparse_mode: true

    - name: loopback
      configuration:
        ospf:
          process_ids:
            - id: 1
              areas: ["0"]
          network_type: point-to-point
        pim:
          sparse_mode: true
```

### Variables and Scope

Variables can be defined at multiple levels with inner scopes overriding outer ones:

| Scope | Where Defined | Example Variables | Availability |
|---|---|---|---|
| **Global** | `iosxe.global.variables` | `bgp_asn`, `anycast_ip` | All devices, all templates |
| **Device Group** | `device_groups[].variables` | `vlan_id`, `mcast_group` | Devices in that group |
| **Device** | `devices[].variables` | `hostname`, `lo0_ip`, `vtep_ip` | That specific device |

Additionally, file-type templates have access to `GLOBAL.devices` — the entire device inventory — enabling dynamic discovery. This is how templates auto-wire BGP neighbors and interfaces:

```hcl
# In underlay_leaf.yaml.tftpl — auto-discover all spines:
%{ for index, device in [for d in GLOBAL.devices : d if contains(d.device_groups, "SPINES")] }
    - ip: ${device.variables.lo0_ip}
      remote_as: ${bgp_asn}
      update_source_interface_type: Loopback
      update_source_interface_id: 0
%{ endfor }
```

### Template Rendering Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│  1. GLOBAL TEMPLATES                                                     │
│     └── global: hostname, IP routing, IPv6, multicast, MTU, Loopback 0  │
│     └── underlay_fabric: OSPF process, BGP AS, PIM SSM + RP            │
│         └── Applied to: ALL devices via device_groups                    │
├─────────────────────────────────────────────────────────────────────────┤
│  2. ROLE-SPECIFIC TEMPLATES                                              │
│     └── underlay_leaf: Lo1, fabric intf, NVE, BGP→spines, EVPN         │
│     └── underlay_spine: Lo100, fabric intf, MSDP, BGP→leaves (RR)      │
│         └── Applied to: LEAFS or SPINES device group                     │
├─────────────────────────────────────────────────────────────────────────┤
│  3. SERVICE TEMPLATES                                                    │
│     └── service_l2: VLAN + EVPN instance + NVE VNI                      │
│     └── service_l3: VRF + VLANs + SVIs + NVE + BGP VRF AF + EVPN      │
│         └── Applied to: SERVICE_xxx device groups (subset of devices)    │
├─────────────────────────────────────────────────────────────────────────┤
│  4. MERGE                                                                │
│     └── Module merges all template outputs per device                    │
│     └── Produces complete device configuration                           │
└─────────────────────────────────────────────────────────────────────────┘
```

### Adding a New Leaf (Walkthrough)

To add `LEAF3` to the fabric, create a single entry in `data/inventory.nac.yaml`:

```yaml
    - name: LEAF3
      host: 10.1.1.5
      device_groups:
        - LEAFS
      variables:
        hostname: LEAF3
        lo0_ip: 10.1.100.5
        vtep_ip: 10.1.200.3
```

**What the templates auto-generate for LEAF3:**
- Loopback 0 with 10.1.100.5/32 (from `global` template)
- Loopback 1 with 10.1.200.3/32 (from `underlay_leaf` template)
- Gi1/0/1 and Gi1/0/2 toward both spines (from `underlay_leaf` template, iterating over SPINES)
- BGP neighbors to SPINE1 and SPINE2 (from `underlay_leaf` template)
- NVE interface sourced from Loopback 1 (from `underlay_leaf` template)
- EVPN global config (from `underlay_leaf` template)
- All L2/L3 services (from service group membership — add `LEAF3` to each SERVICE group)

**What the templates auto-generate on existing spines:**
- Gi1/0/3 interface toward LEAF3 (spine template iterates over LEAFS, now includes LEAF3)
- BGP neighbor 10.1.100.5 with route-reflector-client (spine template auto-discovers new leaf)

**Total lines of YAML written:** ~8. **Total lines of configuration generated:** ~200+ per device.

### Adding a New L2 Service (Walkthrough)

To add VLAN 103 as a new L2 segment, create one file — `data/service_l2_103.nac.yaml`:

```yaml
iosxe:
  device_groups:
    - name: SERVICE_103
      devices:
        - LEAF1
        - LEAF2
      templates: [service_l2]
      variables:
        vlan_id: 103
        mcast_group: 225.1.1.3
```

**What the template auto-generates on every listed leaf:**
- VLAN 103 with name `L2_103`
- EVPN instance 103 (VLAN-based, VXLAN encapsulation)
- NVE member VNI 10103 with multicast group 225.1.1.3

**Total lines of YAML written:** 10. **No changes to any existing file.**

### Adding a New L3 Service (Walkthrough)

To add a new VRF `RED` with tenant VLAN 2001, create one file — `data/service_l3_red.nac.yaml`:

```yaml
iosxe:
  device_groups:
    - name: SERVICE_RED
      devices:
        - LEAF1
        - LEAF2
      templates: [service_l3]
      variables:
        name: RED
        core_vlan_id: 2000
        vlans:
          - id: 2001
```

**What the template auto-generates on every listed leaf:**
- VRF `RED` with RD `65000:2000`, full RT import/export (IPv4 + IPv6)
- Core VLAN 2000 with L3 VNI 202000
- Tenant VLAN 2001 with L2 VNI 102001
- SVI for VLAN 2001 in VRF RED with IP 172.17.1.1/24
- Core SVI for VLAN 2000 (IP unnumbered to Lo1)
- NVE member VNI 102001 (ingress replication) + VNI 202000 (VRF RED)
- BGP IPv4/IPv6 unicast under VRF RED with `advertise l2vpn evpn` + redistribute
- EVPN instance 2001 (VLAN-based, ingress replication, VXLAN encapsulation)

**Total lines of YAML written:** 13. **No changes to any existing file.**

---

## YAML-to-CLI Rendering Examples

**Underlay Leaf — BGP Neighbors (auto-discovered from SPINES group):**

```yaml
# Template: underlay_leaf.yaml.tftpl (rendered for LEAF1)
routing:
  bgp:
    as_number: 65000
    neighbors:
      - ip: 10.1.100.1          # SPINE1 — auto-discovered
        remote_as: 65000
        update_source_interface_type: Loopback
        update_source_interface_id: 0
      - ip: 10.1.100.2          # SPINE2 — auto-discovered
        remote_as: 65000
        update_source_interface_type: Loopback
        update_source_interface_id: 0
```
```
! Rendered IOS-XE CLI
router bgp 65000
 neighbor 10.1.100.1 remote-as 65000
 neighbor 10.1.100.1 update-source Loopback0
 neighbor 10.1.100.2 remote-as 65000
 neighbor 10.1.100.2 update-source Loopback0
```

**Underlay Spine — MSDP Peer (auto-discovered from other spine):**

```yaml
# Template: underlay_spine.yaml.tftpl (rendered for SPINE1)
msdp:
  originator_id_interface_type: Loopback
  originator_id_interface_id: 0
  peers:
    - host: 10.1.100.2          # SPINE2 — auto-discovered
      connect_source_interface_type: Loopback
      connect_source_interface_id: 0
```
```
! Rendered IOS-XE CLI
ip msdp originator-id Loopback0
ip msdp peer 10.1.100.2 connect-source Loopback0
```

**L2 Service — VLAN + EVPN Instance + NVE (from service_l2 template):**

```yaml
# Template: service_l2.yaml.tftpl (rendered for VLAN 101)
vlan:
  vlans:
    - id: 101
      evpn_instance: 101
      evpn_instance_vni: 10101
      name: L2_101
interfaces:
  nves:
    - id: 1
      vnis:
        - vni_from: 10101
          ipv4_multicast_group: 225.1.1.1
evpn:
  instances:
    - number: 101
      vlan_based:
        encapsulation: vxlan
```
```
! Rendered IOS-XE CLI
vlan 101
 name L2_101

l2vpn evpn instance 101 vlan-based
 encapsulation vxlan

interface nve1
 member vni 10101 mcast-group 225.1.1.1
```

**L3 Service — VRF + VLAN + SVI + NVE + BGP (from service_l3 template):**

```yaml
# Template: service_l3.yaml.tftpl (rendered for VRF BLUE, core_vlan 1010, tenant 1011)
vrfs:
  - name: BLUE
    route_distinguisher: "65000:1010"
    address_family_ipv4:
      import_route_targets: ["65000:1010"]
      export_route_targets: ["65000:1010"]
      import_route_targets_stitching: ["65000:1010"]
      export_route_targets_stitching: ["65000:1010"]
```
```
! Rendered IOS-XE CLI
vrf definition BLUE
 rd 65000:1010
 address-family ipv4
  route-target import 65000:1010
  route-target import 65000:1010 stitching
  route-target export 65000:1010
  route-target export 65000:1010 stitching
```

---

## Repository Structure

```
nac-iosxe-vxlan-example/
├── data/                                    # YAML configuration data
│   ├── inventory.nac.yaml                   # Device inventory + global variables
│   ├── templates.nac.yaml                   # Template definitions (model + file refs)
│   ├── interface_groups.nac.yaml            # Reusable interface configuration profiles
│   ├── service_l2_101.nac.yaml              # L2 service: VLAN 101 (multicast)
│   ├── service_l2_102.nac.yaml              # L2 service: VLAN 102 (multicast)
│   ├── service_l3_blue.nac.yaml             # L3 service: VRF BLUE (core 1010, tenant 1011)
│   ├── service_l3_green.nac.yaml            # L3 service: VRF GREEN (core 1000, tenant 1001)
│   └── templates/                           # Terraform template files (.tftpl)
│       ├── underlay_leaf.yaml.tftpl         # Leaf underlay: Lo1, NVE, BGP→spines, EVPN
│       ├── underlay_spine.yaml.tftpl        # Spine underlay: Lo100, MSDP, BGP→leaves (RR)
│       ├── service_l2.yaml.tftpl            # L2 service: VLAN + EVPN instance + NVE VNI
│       └── service_l3.yaml.tftpl            # L3 service: VRF + VLANs + SVIs + BGP + NVE
├── main.tf                                  # Terraform module configuration
├── LICENSE                                  # Apache 2.0
└── README.md                                # This file
```

### Data Files

| File | Purpose | When to Edit |
|---|---|---|
| `inventory.nac.yaml` | Device list, management IPs, global variables, device group assignments | Adding/removing devices, changing IPs or BGP AS |
| `templates.nac.yaml` | Template definitions (model templates inline, file templates by path) | Adding new template types |
| `interface_groups.nac.yaml` | Reusable interface profiles (fabric, loopback) | Changing underlay interface behavior |
| `service_l2_*.nac.yaml` | L2 service definitions (VLAN, multicast group) | Adding/removing L2 segments |
| `service_l3_*.nac.yaml` | L3 service definitions (VRF, core VLAN, tenant VLANs) | Adding/removing VRF tenants |

### Template Files

| File | Variables Used | Dynamic Lookups | Purpose |
|---|---|---|---|
| `underlay_leaf.yaml.tftpl` | `bgp_asn`, `vtep_ip` | Iterates `GLOBAL.devices` filtered by SPINES group | Auto-wires leaf BGP, interfaces, NVE |
| `underlay_spine.yaml.tftpl` | `bgp_asn`, `anycast_ip`, `msdp_peer_ip` | Iterates `GLOBAL.devices` filtered by LEAFS group | Auto-wires spine BGP (RR), interfaces, MSDP |
| `service_l2.yaml.tftpl` | `vlan_id`, `mcast_group` | — | Generates L2 VLAN + EVPN + NVE per service |
| `service_l3.yaml.tftpl` | `bgp_asn`, `name`, `core_vlan_id`, `vlans[]` | — | Generates VRF + VLANs + SVIs + BGP + NVE + EVPN |

### Supporting Files

| File | Purpose |
|---|---|
| `main.tf` | Points to the public NaC IOS-XE Terraform module (`netascode/nac-iosxe/iosxe`) |
| `LICENSE` | Apache 2.0 License |

---

## Prerequisites

| Tool | Version | Installation |
|---|---|---|
| [Terraform](https://www.terraform.io/downloads) | >= 1.8.0 | [Install Guide](https://developer.hashicorp.com/terraform/install) |
| Python | >= 3.9 | System package manager |

**Network Requirements:**
- RESTCONF must be enabled on all target devices
- Management IP reachability from the Terraform host to all devices
- IOS-XE version with full EVPN-VXLAN + PIM support (17.x+)
- Jumbo frame support on all intermediate infrastructure

---

## Quick Start

### 1. Clone the Repository

```shell
git clone https://github.com/netascode/nac-iosxe-vxlan-example.git
cd nac-iosxe-vxlan-example
```

### 2. Set Credentials

```shell
export IOSXE_USERNAME=admin
export IOSXE_PASSWORD=password
```

### 3. Initialize Terraform

Update device management IPs in [`data/inventory.nac.yaml`](data/inventory.nac.yaml) to match your environment, then:

```shell
terraform init
```

### 4. Plan and Apply

```shell
terraform plan
terraform apply
```

### 5. Destroy (Cleanup)

```shell
terraform destroy
```

---

## Verification Commands

After deploying the fabric, use these IOS-XE commands to verify correct operation:

**PIM RP Mapping:**

```
LEAF1# show ip pim rp mapping

PIM Group-to-RP Mappings
  Group(s): 224.0.0.0/4, Static
    RP: 10.1.101.1
```

**PIM Neighbors (leaf view):**

```
LEAF1# show ip pim neighbor

PIM Neighbor Table
Neighbor       Interface          Uptime    Expires   DR Priority
10.1.100.1     Gi1/0/1            ...       ...       1
10.1.100.2     Gi1/0/2            ...       ...       1
```

**MSDP Peer Status (spine view):**

```
SPINE1# show ip msdp peer

MSDP Peer 10.1.100.2, AS 0
  Connection status: Up
  Connect source: Loopback0
```

**NVE Interface (note Loopback1 source):**

```
LEAF1# show nve interface nve1

Interface: nve1, State: Admin Up, Oper Up, Encapsulation: VXLAN
 Source-Interface: Loopback1 (primary: 10.1.200.1)
 Host Learning: bgp
```

**NVE VNI Mapping:**

```
LEAF1# show nve vni

Interface  VNI        Multicast-group  VNI state  Mode  VLAN  Cfg
nve1       10101      225.1.1.1        Up         L2CP  101   CLI
nve1       10102      225.1.1.2        Up         L2CP  102   CLI
nve1       101001     N/A              Up         L2CP  1001  CLI
nve1       101011     N/A              Up         L2CP  1011  CLI
nve1       201000     N/A              Up         L3CP  1000  CLI
nve1       201010     N/A              Up         L3CP  1010  CLI
```

**OSPF Neighbors (spine view — 2 leaf adjacencies):**

```
SPINE1# show ip ospf neighbor

Neighbor ID     Pri   State      Dead Time   Address        Interface
10.1.100.3        0   FULL/  -   00:00:39    10.1.100.3     Gi1/0/1
10.1.100.4        0   FULL/  -   00:00:36    10.1.100.4     Gi1/0/2
```

**BGP L2VPN EVPN Summary (spine — route-reflector view):**

```
SPINE1# show bgp l2vpn evpn summary

BGP router identifier 10.1.100.1, local AS number 65000
Neighbor        V    AS  State/PfxRcd
10.1.100.3      4  65000  ...         ← LEAF1 (RR client)
10.1.100.4      4  65000  ...         ← LEAF2 (RR client)
```

---

## Configuration Patterns Demonstrated

| Pattern | Where | Description |
|---|---|---|
| **Template-driven device config** | All devices | Variables + templates generate full config — no per-device YAML |
| **Interface groups** | All devices | Reusable OSPF + PIM profiles applied by name |
| **IP unnumbered underlay** | All fabric links | No per-link /31 subnets — simplifies address planning |
| **Route-reflector BGP** | Spines | Leaves peer only with spines — scales better than full mesh |
| **Auto-discovered neighbors** | Templates | `GLOBAL.devices` lookup auto-wires BGP + interfaces |
| **Composable L2 services** | `service_l2_*.yaml` | One file per L2 segment, applied to any subset of leaves |
| **Composable L3 services** | `service_l3_*.yaml` | One file per VRF, generates full VRF + VLANs + SVIs + NVE + BGP |
| **Dedicated VTEP Loopback** | Leaves | Loopback 1 for NVE/EVPN, separate from Lo0 routing RID |
| **Anycast RP** | Spines | Shared Loopback 100 IP for PIM RP redundancy |
| **MSDP Peering** | Spines | Multicast source sync between anycast RP peers |
| **PIM Sparse-Mode** | All devices | On every fabric interface and loopback (via interface groups) |
| **PIM SSM** | All devices | Source Specific Multicast enabled globally |
| **Multicast + Ingress BUM** | Leaves | Per-service choice: multicast groups or ingress replication |
| **EVPN Default GW Advertise** | Leaves | Anycast gateway MAC in Type-2 routes |
| **Route Target Auto VNI** | Leaves | Automatic RT derivation from VNI values |
| **no bgp default ipv4-unicast** | All devices | Explicit per-AF neighbor activation |
| **Jumbo MTU (8978)** | All devices | For VXLAN overhead |
| **Dual-stack IPv4/IPv6** | VRFs | Both address families configured per VRF |

---

## Best Practices

1. **Template-Driven Operations**: Define devices with minimal variables and let templates generate the configuration. This ensures consistency across all devices and eliminates copy-paste drift.

2. **Interface Groups for Consistency**: Use interface groups (`fabric`, `loopback`) to enforce identical OSPF + PIM configuration on all interfaces of the same type. Never manually configure these per-interface.

3. **IP Unnumbered Underlay**: Use IP unnumbered to Loopback 0 for all fabric links. This eliminates per-link subnet planning and makes adding new links trivial.

4. **Route-Reflectors for Scale**: Deploy spines as iBGP route-reflectors so adding a new leaf only requires peering with spines. Templates handle this automatically.

5. **Separate VTEP Identity from Routing Identity**: Use Loopback 1 for NVE source and EVPN router-id, keeping Loopback 0 for OSPF RID and BGP router-id.

6. **Anycast RP with MSDP**: Deploy the PIM RP as an anycast address shared between both spines, synchronized via MSDP for RP redundancy.

7. **PIM Sparse-Mode Everywhere**: Enable PIM sparse-mode on every fabric-facing interface and loopback via interface groups. Without it, multicast BUM traffic cannot form distribution trees.

8. **Jumbo MTU**: Set the system MTU to 8978 across all fabric devices. VXLAN adds 50-54 bytes of overhead; jumbo frames prevent fragmentation.

9. **`no bgp default ipv4-unicast`**: Disable automatic IPv4 activation on BGP neighbors. Explicitly activate only the required address families per peer.

10. **One Service File per Segment/VRF**: Each L2 service and L3 VRF gets its own YAML file. This makes Day 2 operations atomic — add a file to add a service, delete a file to remove it.

11. **`route-target auto vni`**: Use automatic route target derivation from VNI values to reduce manual RT configuration and prevent mismatches.

---

## Documentation

| Resource | URL |
|---|---|
| NaC Documentation | [https://netascode.cisco.com](https://netascode.cisco.com) |
| NaC IOS-XE Module | [Terraform Registry](https://registry.terraform.io/modules/netascode/nac-iosxe/iosxe) |
| IOS-XE Provider | [Terraform Registry](https://registry.terraform.io/providers/CiscoDevNet/iosxe) |
| Per-Device EVPN-VXLAN Example | [GitHub](https://github.com/netascode/nac-iosxe-campus-evpn-vxlan-example) |
