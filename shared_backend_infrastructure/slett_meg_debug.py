#!/usr/bin/env python3
import ipaddress
import sys


def parse_cidr_ranges(existing_subnets):
    """
    Convert CIDR ranges to ipaddress network objects and print their details.

    :param existing_subnets: List of CIDR ranges as strings
    :return: List of ipaddress.IPv4Network objects
    """
    print("\nExisting Subnets:")
    parsed_networks = []
    for subnet_str in existing_subnets:
        network = ipaddress.IPv4Network(subnet_str, strict=False)
        parsed_networks.append(network)
        print(f"Subnet: {subnet_str}")
        print(f"  First IP: {network[0]}")
        print(f"  Last IP:  {network[-1]}")
        print(f"  Total IPs: {network.num_addresses}\n")
    return parsed_networks


def subnets_overlap(subnet1, subnet2):
    """
    Check if two subnets overlap.

    :param subnet1: First subnet as ipaddress.IPv4Network
    :param subnet2: Second subnet as ipaddress.IPv4Network
    :return: True if subnets overlap, False otherwise
    """
    return subnet1.overlaps(subnet2)


def find_next_free_subnet(vnet_cidr, existing_networks, subnet_mask=27):
    """
    Find the next available subnet range within a VNet CIDR block.

    :param vnet_cidr: CIDR range of the Virtual Network
    :param existing_networks: List of existing subnet networks
    :param subnet_mask: Desired subnet mask (default /27)
    :return: Next available subnet range as a string
    """
    # Convert VNet and existing subnets to network objects
    vnet = ipaddress.IPv4Network(vnet_cidr, strict=False)
    used_networks = parse_cidr_ranges(existing_networks)

    print("\nSearching for next free subnet...")
    # Iterate through all possible subnets in the VNet with the specified mask
    for subnet in vnet.subnets(new_prefix=subnet_mask):
        print(f"\nChecking potential subnet: {subnet}")
        print(f"  First IP: {subnet[0]}")
        print(f"  Last IP:  {subnet[-1]}")

        # Check if the subnet does not overlap with any existing subnets
        overlaps = any(subnets_overlap(subnet, existing) for existing in used_networks)

        if not overlaps:
            print("  ✅ No overlap found!")
            return str(subnet)
        else:
            print("  ❌ Overlaps with existing subnet")

    # If no free subnet found
    raise ValueError("No free subnet found in the given VNet CIDR range")


def main():
    # Exact subnets from Azure CLI output
    vnet_cidr = "10.0.0.0/16"
    existing_subnets = [
        "10.0.0.32/27",  # private-we-prod
        "10.0.0.0/27",  # public-we-prod
        "10.0.0.128/27",  # pubsub-subnet
        "10.0.0.64/27",  # container-subnet
        "10.0.2.0/24",  # jumpbox-subnet
        "10.0.1.0/26",  # AzureBastionSubnet
    ]

    # Allow configuration via command-line arguments
    if len(sys.argv) > 1:
        vnet_cidr = sys.argv[1]

    # Use /27 subnet mask
    subnet_mask = 27

    try:
        # Find the next available subnet
        available_subnet = find_next_free_subnet(vnet_cidr, existing_subnets, subnet_mask)

        # Print detailed results
        print("\n🎉 Result:")
        print(f"Next available /27 subnet in {vnet_cidr}:")
        print(available_subnet)

        # Get detailed info about the subnet
        subnet_obj = ipaddress.IPv4Network(available_subnet, strict=False)
        print(f"  First IP: {subnet_obj[0]}")
        print(f"  Last IP:  {subnet_obj[-1]}")
        print(f"  Total IPs: {subnet_obj.num_addresses}")
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()