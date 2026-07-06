import subprocess
import sys

HOST = "192.168.178.151"
USER = "root"
IMG_PATH = "/guests/android/sdcard_virtio.img"

# Super partition starts at LBA 563200 (byte 288,358,400)
START_OFFSET = 288358400

# String to search for (extremely unique in fstab)
PATTERN = b"/dev/block/by-name/metadata /metadata"

def stream_and_find():
    print(f"Streaming from {IMG_PATH} starting at offset {START_OFFSET}...")
    
    # We use dd to stream in 1MB blocks
    skip_mb = START_OFFSET // (1024 * 1024)
    cmd = [
        "ssh", "-o", "StrictHostKeyChecking=no", f"{USER}@{HOST}",
        f"dd if={IMG_PATH} bs=1M skip={skip_mb} 2>/dev/null"
    ]
    
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, bufsize=1024*1024)
    
    bytes_read = 0
    buffer = b""
    found_offset_in_stream = -1
    
    chunk_size = 10 * 1024 * 1024
    
    try:
        while True:
            chunk = proc.stdout.read(chunk_size)
            if not chunk:
                break
            
            buffer += chunk
            idx = buffer.find(PATTERN)
            if idx != -1:
                found_offset_in_stream = bytes_read + idx
                break
            
            bytes_read += len(chunk)
            buffer = buffer[-len(PATTERN):]
            
            print(f"Checked {bytes_read / (1024*1024):.1f} MB...", end="\r")
            
    finally:
        proc.terminate()
        proc.wait()
        
    if found_offset_in_stream != -1:
        absolute_offset = START_OFFSET + found_offset_in_stream
        print(f"\nFound pattern at absolute offset: {absolute_offset} bytes")
        return absolute_offset
    else:
        print("\nPattern not found in the super partition.")
        return None

def read_block(offset, size):
    cmd = [
        "ssh", "-o", "StrictHostKeyChecking=no", f"{USER}@{HOST}",
        f"dd if={IMG_PATH} bs=1 count={size} skip={offset} 2>/dev/null"
    ]
    res = subprocess.run(cmd, capture_output=True)
    return res.stdout

def write_block(offset, data):
    cmd = [
        "ssh", "-o", "StrictHostKeyChecking=no", f"{USER}@{HOST}",
        f"dd of={IMG_PATH} bs=1 seek={offset} conv=notrunc 2>/dev/null"
    ]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    stdout, stderr = p.communicate(input=data)
    if p.returncode != 0:
        print(f"Error writing: {stderr.decode()}", file=sys.stderr)
        sys.exit(1)

def main():
    fstab_offset = stream_and_find()
    if fstab_offset is None:
        sys.exit(1)
        
    # Read 1200 bytes before fstab_offset to capture system /system
    read_start = fstab_offset - 1000
    print(f"Reading fstab block from offset {read_start}...")
    block = read_block(read_start, 2048)
    
    # Find the start of the fstab text
    start_idx = block.find(b"system /system ")
    if start_idx == -1:
        start_idx = block.find(b"system\t/system")
        
    if start_idx == -1:
        print("Error: Could not identify the start of the fstab file in the block!")
        print("\nRaw block content (first 800 bytes):")
        print(block[:800].decode('utf-8', errors='replace'))
        sys.exit(1)
        
    actual_fstab_offset = read_start + start_idx
    print(f"Verified fstab file starts at absolute offset: {actual_fstab_offset}")
    
    # Read the original fstab content (1500 bytes should be plenty)
    original_fstab = read_block(actual_fstab_offset, 1500)
    
    # Extract original text lines until the end of the fstab block (usb auto auto line)
    lines = original_fstab.split(b"\n")
    valid_lines = []
    total_len = 0
    for line in lines:
        if b"voldmanaged=usb:auto" in line or b"usb" in line:
            valid_lines.append(line)
            total_len += len(line) + 1
            break
        valid_lines.append(line)
        total_len += len(line) + 1
        
    original_fstab_text = b"\n".join(valid_lines)
    original_size = len(original_fstab_text)
    
    print("\n--- ORIGINAL FSTAB CONTENT ---")
    print(original_fstab_text.decode("utf-8", errors="replace"))
    print(f"--- Size: {original_size} bytes ---\n")
    
    # Construct the new fstab text! We keep everything exactly as original but strip quota and encryption from userdata
    # We reconstruct the fstab exactly based on the original content, only replacing the userdata line.
    
    # Let's rebuild the lines
    new_lines = []
    for line in valid_lines:
        if b"/dev/block/by-name/userdata" in line:
            # Replaced line:
            new_line = b"/dev/block/by-name/userdata /data ext4 noatime,nosuid,nodev,barrier=1 wait,check,latemount,formattable"
            new_lines.append(new_line)
        else:
            new_lines.append(line)
            
    new_fstab_text = b"\n".join(new_lines)
    new_size = len(new_fstab_text)
    
    print("--- NEW FSTAB CONTENT ---")
    print(new_fstab_text.decode("utf-8"))
    print(f"--- Size: {new_size} bytes ---\n")
    
    if new_size > original_size:
        print(f"Error: New fstab size ({new_size}) is larger than original fstab size ({original_size})!")
        sys.exit(1)
        
    # Pad the new fstab with spaces to match the exact original size so we don't leave junk at the end
    padding_len = original_size - new_size
    padded_fstab = new_fstab_text + b" " * padding_len
    
    assert len(padded_fstab) == original_size
    
    # Write the padded fstab back to the disk image!
    print(f"Writing padded new fstab of size {len(padded_fstab)} bytes back to offset {actual_fstab_offset}...")
    write_block(actual_fstab_offset, padded_fstab)
    print("Fstab patched successfully on the virtual disk!")

if __name__ == "__main__":
    main()
