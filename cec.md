# Command

```sh
/nix/store/jmayglfxhi9nnph33fn90v6l0f4sl9s2-python3-3.13.13-env/bin/python3 -c '
import cec, threading

cec.set_physical_addr("1.6.0.0")
cec.init()

def on_cmd(event, cmd):
    opcode = cmd.get("opcode")
    initiator = cmd.get("initiator")
    params = cmd.get("parameters", b"")
    print(f"opcode={opcode:#04x}({opcode}) initiator={initiator} params={params.hex()}", flush=True)

cec.add_callback(on_cmd, cec.EVENT_COMMAND)
print("monitoring — turn things on/off, switch sources", flush=True)
threading.Event().wait(300)
'
```

# Scnearios

## Turn on AVR, chromecast was the active source. Projector does not turn on automatically

```
monitoring — turn things on/off, switch sources
opcode=0x87(135) initiator=0 params=000000
opcode=0x90(144) initiator=0 params=00
opcode=0x72(114) initiator=5 params=01
opcode=0x84(132) initiator=0 params=000000
opcode=0x84(132) initiator=8 params=120004
opcode=0x46(70) initiator=5 params=
opcode=0x83(131) initiator=5 params=
opcode=0x84(132) initiator=0 params=000000
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=8 params=
opcode=0x46(70) initiator=8 params=
opcode=0x46(70) initiator=8 params=
opcode=0x83(131) initiator=5 params=
opcode=0x84(132) initiator=5 params=100005
opcode=0x87(135) initiator=5 params=0005cd
opcode=0xa7(167) initiator=5 params=0000
opcode=0x85(133) initiator=5 params=
opcode=0x80(128) initiator=5 params=11001200
opcode=0xa6(166) initiator=8 params=06105800
opcode=0x84(132) initiator=8 params=120004
opcode=0x87(135) initiator=8 params=1ca410
opcode=0x82(130) initiator=8 params=1200
opcode=0x90(144) initiator=8 params=00
opcode=0x8f(143) initiator=8 params=`
```

## Turn off AVR, chromecast was the active source. Projector was turned off

```
monitoring — turn things on/off, switch sources
opcode=0x84(132) initiator=0 params=000000
opcode=0x83(131) initiator=8 params=
opcode=0x46(70) initiator=5 params=
opcode=0x84(132) initiator=0 params=000000
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=5 params=
opcode=0x84(132) initiator=5 params=100005
opcode=0x84(132) initiator=0 params=000000
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=8 params=
opcode=0x46(70) initiator=8 params=
opcode=0x46(70) initiator=8 params=
opcode=0x46(70) initiator=8 params=
opcode=0x90(144) initiator=8 params=01
```

## Turn on Projector. AVR was off

```
monitoring — turn things on/off, switch sources
opcode=0x87(135) initiator=0 params=000000
opcode=0x87(135) initiator=0 params=000000
opcode=0x87(135) initiator=0 params=000000
```

## Turn off Projector. AVR was off

```
monitoring — turn things on/off, switch sources
opcode=0x36(54) initiator=0 params=
```

## Turn off Projector. AVR was on. Mini PC was active source. AVR was also turned off

```
monitoring — turn things on/off, switch sources
opcode=0x36(54) initiator=0 params=
opcode=0x80(128) initiator=5 params=16001100
```

## Switch source from Mini PC to Chromecast in AVR

```
monitoring — turn things on/off, switch sources
monitoring — turn things on/off, switch sources
opcode=0x80(128) initiator=5 params=16001200
opcode=0xa6(166) initiator=8 params=06105800
opcode=0x84(132) initiator=8 params=120004
opcode=0x87(135) initiator=8 params=1ca410
opcode=0x82(130) initiator=8 params=1200
opcode=0x90(144) initiator=8 params=00
opcode=0xa6(166) initiator=8 params=06105800
opcode=0x84(132) initiator=8 params=120004
opcode=0x87(135) initiator=8 params=1ca410
opcode=0x84(132) initiator=5 params=100005
opcode=0x84(132) initiator=0 params=000000
opcode=0x83(131) initiator=8 params=
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=0 params=000000
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=8 params=
opcode=0x46(70) initiator=0 params=
opcode=0x87(135) initiator=5 params=0005cd
opcode=0x8c(140) initiator=8 params=
opcode=0x87(135) initiator=0 params=000000
opcode=0x90(144) initiator=0 params=00
opcode=0x8f(143) initiator=8 params=
```

## Switch source from Chromecast to Mini PC in AVR

```
monitoring — turn things on/off, switch sources
opcode=0x80(128) initiator=5 params=12001600
opcode=0x87(135) initiator=0 params=000000
opcode=0x87(135) initiator=0 params=000000
opcode=0x90(144) initiator=0 params=00
opcode=0xa6(166) initiator=8 params=06105800
opcode=0x84(132) initiator=8 params=120004
opcode=0x87(135) initiator=8 params=1ca410
opcode=0x90(144) initiator=0 params=00
opcode=0xa6(166) initiator=8 params=06105800
opcode=0x84(132) initiator=8 params=120004
opcode=0x87(135) initiator=8 params=1ca410
opcode=0x84(132) initiator=5 params=100005
opcode=0x84(132) initiator=0 params=000000
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=0 params=
opcode=0x83(131) initiator=8 params=
opcode=0x84(132) initiator=0 params=000000
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=0 params=
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=8 params=
opcode=0x87(135) initiator=5 params=0005cd
opcode=0x8c(140) initiator=8 params=
opcode=0x87(135) initiator=0 params=000000
opcode=0x90(144) initiator=0 params=00
opcode=0x8f(143) initiator=8 params=
```

## Trigger source switch from Chromecast to Chromecast

```
monitoring — turn things on/off, switch sources
opcode=0x82(130) initiator=8 params=1200
opcode=0x72(114) initiator=5 params=01
opcode=0x82(130) initiator=8 params=1200
opcode=0xa6(166) initiator=8 params=06105800
opcode=0x84(132) initiator=8 params=120004
opcode=0x87(135) initiator=8 params=1ca410
opcode=0x84(132) initiator=5 params=100005
opcode=0x84(132) initiator=0 params=000000
opcode=0x83(131) initiator=8 params=
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=0 params=000000
opcode=0x46(70) initiator=5 params=
opcode=0x46(70) initiator=8 params=
opcode=0x46(70) initiator=0 params=
z opcode=0x87(135) initiator=5 params=0005cd
opcode=0x8c(140) initiator=8 params=
opcode=0x87(135) initiator=0 params=000000
opcode=0x90(144) initiator=0 params=00
opcode=0x8f(143) initiator=8 params=
```
