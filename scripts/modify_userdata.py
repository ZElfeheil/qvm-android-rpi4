import subprocess
import struct
import sys

HOST = "192.168.178.151"
USER = "root"
IMG_PATH = "/guests/android/sdcard_virtio.img"

def run_ssh_read(offset_bytes, size_bytes):
    # We use dd to read specific bytes
    # To be safe and precise, we read at byte level using bs=1 count=size_bytes skip=offset_bytes
    cmd = [
        "ssh", "-o", "StrictHostKeyChecking=no", f"{USER}@{HOST}",
        f"dd if={IMG_PATH} bs=1 count={size_bytes} skip={offset_bytes} 2>/dev/null"
    ]
    result = subprocess.run(cmd, capture_output=True)
    if result.returncode != 0:
        print(f"Error running SSH command: {result.stderr.decode()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout

def run_ssh_write_bytes(offset_bytes, data):
    # We write specific bytes using dd
    # bs=1 seek=offset_bytes conv=notrunc
    cmd = [
        "ssh", "-o", "StrictHostKeyChecking=no", f"{USER}@{HOST}",
        f"dd of={IMG_PATH} bs=1 seek={offset_bytes} conv=notrunc 2>/dev/null"
    ]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = p.communicate(input=data)
    if p.returncode != 0:
        print(f"Error writing: {stderr.decode()}", file=sys.stderr)
        sys.exit(1)

def parse_gpt():
    print("Reading GPT Header and Partition Table...")
    # Read LBA 0, 1, and 2-33 (34 sectors = 17408 bytes)
    gpt_data = run_ssh_read(0, 17408)
    if len(gpt_data) < 17408:
        print(f"Failed to read GPT table (read {len(gpt_data)} bytes)", file=sys.stderr)
        sys.exit(1)

    # GPT Header is at LBA 1 (offset 512)
    # Signature is "EFI PART" (8 bytes) at offset 512
    signature = gpt_data[512:520]
    if signature != b"EFI PART":
        print(f"Invalid GPT Signature: {signature}", file=sys.stderr)
        sys.exit(1)

    # Partition Entry LBA is at offset 512 + 72 (8 bytes)
    # Number of Partition Entries is at offset 512 + 80 (4 bytes)
    # Size of each Partition Entry is at offset 512 + 84 (4 bytes)
    part_entry_lba = struct.unpack("<Q", gpt_data[512+72:512+80])[0]
    num_parts = struct.unpack("<I", gpt_data[512+80:512+84])[0]
    part_size = struct.unpack("<I", gpt_data[512+84:512+88])[0]

    print(f"GPT Header: Partition Entry LBA={part_entry_lba}, Num Entries={num_parts}, Entry Size={part_size}")

    # Partition entries start at part_entry_lba * 512
    start_offset = part_entry_lba * 512

    userdata_lba = None
    for i in range(num_parts):
        entry_offset = start_offset + i * part_size
        entry = gpt_data[entry_offset : entry_offset + part_size]
        if len(entry) < 128:
            break
        
        # Partition Type GUID (16 bytes)
        type_guid = entry[0:16]
        if type_guid == b"\x00" * 16:
            continue # Unused
        
        # Starting LBA (8 bytes)
        start_lba = struct.unpack("<Q", entry[32:40])[0]
        # Ending LBA (8 bytes)
        end_lba = struct.unpack("<Q", entry[40:48])[0]
        # Name (72 bytes, UTF-16LE)
        name_bytes = entry[56:128]
        name = name_bytes.decode("utf-16-le").strip("\x00")

        print(f"Partition {i+1}: Name='{name}', Start LBA={start_lba}, End LBA={end_lba}")
        if name == "userdata":
            userdata_lba = start_lba

    return userdata_lba

def main():
    userdata_lba = parse_gpt()
    if userdata_lba is None:
        print("Error: Could not find 'userdata' partition in GPT table!", file=sys.stderr)
        sys.exit(1)

    userdata_offset = userdata_lba * 512
    print(f"\nUserdata Partition found at byte offset: {userdata_offset}")

    # The superblock is 1024 bytes starting at offset 1024 from the partition start
    sb_offset = userdata_offset + 1024
    print(f"Reading ext4 superblock from offset: {sb_offset}...")
    sb_data = run_ssh_read(sb_offset, 1024)

    # Magic number at offset 0x38 (2 bytes)
    magic = struct.unpack("<H", sb_data[0x38:0x3A])[0]
    if magic != 0xEF53:
        print(f"Error: Invalid ext4 magic number {magic:04X} (expected EF53)!", file=sys.stderr)
        sys.exit(1)
    print("Verified ext4 magic number: EF53")

    # Read s_feature_ro_compat at offset 0x64 (4 bytes)
    feature_ro_compat = struct.unpack("<I", sb_data[0x64:0x68])[0]
    print(f"Current s_feature_ro_compat: {feature_ro_compat:08X}")

    # EXT4_FEATURE_RO_COMPAT_QUOTA flag is 0x0100
    EXT4_FEATURE_RO_COMPAT_QUOTA = 0x00000100

    if feature_ro_compat & EXT4_FEATURE_RO_COMPAT_QUOTA:
        print("Quota feature is ENABLED. Disabling it...")
        new_feature_ro_compat = feature_ro_compat & ~EXT4_FEATURE_RO_COMPAT_QUOTA
        print(f"New s_feature_ro_compat: {new_feature_ro_compat:08X}")

        # Write the 4 bytes back
        new_bytes = struct.pack("<I", new_feature_ro_compat)
        run_ssh_write_bytes(sb_offset + 0x64, new_bytes)
        print("Superblock patched successfully!")
    else:
        print("Quota feature is already DISABLED.")

if __name__ == "__main__":
    main()
