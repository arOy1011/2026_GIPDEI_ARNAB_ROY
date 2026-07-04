import asyncio
from bleak import BleakClient, BleakScanner

SERVICE_UUID = "12345678-1234-1234-1234-1234567890ab"
CMD_UUID = "12345678-1234-1234-1234-1234567890ae"
FILE_UUID = "12345678-1234-1234-1234-1234567890ad"

current_file = None
transfer_event = asyncio.Event()
waiting_for_transfer = False


def notification_handler(sender, data):
    global current_file
    global waiting_for_transfer

    line = data.decode(errors="ignore").strip()

    print(f"RX: {line}")

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

    if current_file is not None:
        if line in ("EOF", "END"):
            current_file.close()
            current_file = None
            waiting_for_transfer = False
            transfer_event.set()
            print("DOWNLOAD COMPLETE")
        elif line.startswith("BEGIN:"):
            print(f"TRANSFER HEADER: {line}")
        else:
            current_file.write(line + "\n")

    elif waiting_for_transfer and line in ("EOF", "END"):
        waiting_for_transfer = False
        transfer_event.set()


async def find_device():
    print("Scanning for MotionLogger...")

    devices = await BleakScanner.discover(return_adv=True)

    for _, (device, adv) in devices.items():
        if SERVICE_UUID.lower() in [s.lower() for s in adv.service_uuids]:
            return device

    return None


async def main():
    global current_file
    global waiting_for_transfer

    device = await find_device()

    if device is None:
        print("MotionLogger not found")
        return

    print(f"Found: {device.name}")
    print(f"Address: {device.address}")

    async with BleakClient(device) as client:

        print("Connected")

        await client.start_notify(FILE_UUID, notification_handler)

        print("Notifications enabled")

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

            transfer_event.clear()

            if cmd == "LIST":
                waiting_for_transfer = True

                await client.write_gatt_char(
                    CMD_UUID,
                    cmd.encode(),
                    response=True
                )

                await transfer_event.wait()
                continue

            if cmd.startswith("G:"):
                index = cmd[2:]

                current_file = open(
                    f"downloaded_{index}.csv",
                    "w"
                )

                waiting_for_transfer = True

                print(
                    f"Downloading file index {index}"
                )

                await client.write_gatt_char(
                    CMD_UUID,
                    cmd.encode(),
                    response=True
                )

                await transfer_event.wait()
                continue

            if cmd.startswith("D:"):
                waiting_for_transfer = True

                await client.write_gatt_char(
                    CMD_UUID,
                    cmd.encode(),
                    response=True
                )

                await transfer_event.wait()
                continue

            await client.write_gatt_char(
                CMD_UUID,
                cmd.encode(),
                response=True
            )

            await asyncio.sleep(0.5)

        await client.stop_notify(FILE_UUID)

    print("Disconnected")


if __name__ == "__main__":
    asyncio.run(main())