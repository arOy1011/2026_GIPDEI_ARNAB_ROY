"""
Simple BLE client for MotionLogger.

Usage summary:
- Scans for a device advertising the `SERVICE_UUID`.
- Connects and subscribes to `FILE_UUID` notifications to receive file
  listings and transfers.
- Sends text commands to `CMD_UUID` to control the logger (START/STOP/LIST/G:<n>/D:<n>/STATUS).

This script uses an asyncio event loop and `bleak` for BLE operations.
"""

import asyncio
from bleak import BleakClient, BleakScanner

SERVICE_UUID = "12345678-1234-1234-1234-1234567890ab"
CMD_UUID = "12345678-1234-1234-1234-1234567890ae"
FILE_UUID = "12345678-1234-1234-1234-1234567890ad"

# Globals used by notification handler and main loop
current_file = None                # file object while downloading a file
transfer_event = asyncio.Event()   # signals completion of LIST/GET/DELETE
waiting_for_transfer = False       # indicates we expect an EOF/END reply


def notification_handler(sender, data):
    """Callback for notifications coming from `FILE_UUID`.

    Expected messages from device:
    - Filenames streamed during LIST, with a final "EOF" marker.
    - "BEGIN:<filesize>" header before a binary file transfer.
    - Raw chunk lines (text) or binary chunks; client writes these
      to `current_file` when downloading.
    - "END" (or "EOF") to mark transfer completion.
    - "DELETE_OK" / "DELETE_FAILED" responses for delete commands.
    """

    global current_file
    global waiting_for_transfer

    line = data.decode(errors="ignore").strip()

    print(f"RX: {line}")

    # Delete responses are one-shot: wake the waiting task and report result
    if line == "DELETE_OK":
        print("DELETE SUCCESS")
        waiting_for_transfer = False
        transfer_event.set()
        return

    if line == "DELETE_FAILED":
        print("DELETE FAILED")
        waiting_for_transfer = False
        transfer_event.set()
        return

    # If a file is currently open, we are in download mode: write incoming
    # chunks until we receive the END/EOF marker.
    if current_file is not None:
        if line in ("EOF", "END"):
            current_file.close()
            current_file = None
            waiting_for_transfer = False
            transfer_event.set()
            print("DOWNLOAD COMPLETE")
        elif line.startswith("BEGIN:"):
            # BEGIN header contains file size; useful for progress reporting
            print(f"TRANSFER HEADER: {line}")
        else:
            # Append received text line to the open file
            current_file.write(line + "\n")

    # If we expected a transfer but no file object is open, treat EOF/END
    # as the completion signal for LIST responses.
    elif waiting_for_transfer and line in ("EOF", "END"):
        waiting_for_transfer = False
        transfer_event.set()


async def find_device():
    """Scan nearby BLE devices and return the first device advertising
    `SERVICE_UUID`. Returns None if not found.
    """

    print("Scanning for MotionLogger...")

    # Use bleak scanner and request advertising data to inspect service UUIDs
    devices = await BleakScanner.discover(return_adv=True)

    for _, (device, adv) in devices.items():
        if SERVICE_UUID.lower() in [s.lower() for s in adv.service_uuids]:
            return device

    return None


async def main():
    global current_file
    global waiting_for_transfer

    """Main client routine:

    - Find and connect to the MotionLogger device.
    - Subscribe to file notifications (`FILE_UUID`) so incoming LIST/GET data
      is handled by `notification_handler`.
    - Present a simple interactive prompt to the user. Commands typed are
      forwarded to the device over `CMD_UUID`.
    - For LIST/G:<n>/D:<n> commands the code sets `waiting_for_transfer` and
      waits on `transfer_event` which is triggered by `notification_handler`.
    """

    device = await find_device()

    if device is None:
        print("MotionLogger not found")
        return

    print(f"Found: {device.name}")
    print(f"Address: {device.address}")

    # Connect using bleak client context manager
    async with BleakClient(device) as client:

        print("Connected")

        # Start receiving notifications for file/command responses
        await client.start_notify(FILE_UUID, notification_handler)

        print("Notifications enabled")

        # Interactive command loop
        while True:
            print("\nCommands:")
            print("STATUS")
            print("START")
            print("STOP")
            print("LIST")
            print("G:<index>")
            print("D:<index>")
            print("EXIT")

            cmd = (await asyncio.to_thread(input, "\nCommand> ")).strip()

            if not cmd:
                continue

            if cmd.upper() == "EXIT":
                break

            # Clear event before issuing a command that expects a reply
            transfer_event.clear()

            if cmd == "LIST":
                # Request listing; wait for EOF notification
                waiting_for_transfer = True

                await client.write_gatt_char(
                    CMD_UUID,
                    cmd.encode(),
                    response=True
                )

                await transfer_event.wait()
                continue

            if cmd.startswith("G:"):
                # Prepare local file to receive download, then request it
                index = cmd[2:]

                current_file = open(f"downloaded_{index}.csv", "w")

                waiting_for_transfer = True

                print(f"Downloading file index {index}")

                await client.write_gatt_char(
                    CMD_UUID,
                    cmd.encode(),
                    response=True
                )

                await transfer_event.wait()
                continue

            if cmd.startswith("D:"):
                # Delete command: wait for DELETE_OK / DELETE_FAILED
                waiting_for_transfer = True

                await client.write_gatt_char(
                    CMD_UUID,
                    cmd.encode(),
                    response=True
                )

                await transfer_event.wait()
                continue

            # All other commands: just send and pause briefly
            await client.write_gatt_char(CMD_UUID, cmd.encode(), response=True)

            await asyncio.sleep(0.5)

        await client.stop_notify(FILE_UUID)

    print("Disconnected")


if __name__ == "__main__":
    asyncio.run(main())