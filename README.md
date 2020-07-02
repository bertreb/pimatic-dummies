# pimatic-dummies
Pimatic plugin for extra dummy devices

This plugin creates dummy devices to use within Pimatic. Dummy device are mostly used for user interaction via the gui and rule based actions. Dummy devices do not directly control a device.

The plugin supports 2 devices; DummyLedLight and DummyLightRGBW

DummyLedLight
----
The DummyLedLight device is a renewed pimatic-led-light device made useable with node 8+. Its a dimmer actuator device with brightness (the dimmer), color temperature and color (RGB).

The device can be controlled via the gui and via rules.

The rules syntax:

`
set <DummyLedLight device> to [<hex color> | <colorname> | temperature based color by variable <$variable>
`

DummyLightRGBW
----
The DummyLightRGBW device is a dimmer actuator device with brightness (the dimmer), color temprature and color (RGB).
This device is based on the RaspBee-RGBCT device from [treban](https://github.com/treban/pimatic-raspbee)

![](/screens/dummy-rgbw.png)

The device can be controlled via the gui and via rules.

The rules syntax:

`
set <DummyLightRGBW device> to [<hex color> | <colorname> | <temperature> | <$variable>]
`

#### Color definitions

`
<hex color> is in the format #[0-F][0-F][0-F][0-F][0-F][0-F] like #1F00A0
`

\<color names> can be found in color_schema.json

\<temperature> must be between 0-100

For the content of the variable, the same color logic applies

DummyThermostat
----
The DummyThermostat device is a thermostat device with a heat, heatcool and cool mode.

![](/screens/dummy-thermostat.png)

The device can be controlled via the gui and via rules.

The rules syntax:

`
thermostat <DummyThermostat device> [
	heat | heatcool | cool |
	on | eco | off |
	setpoint [<temperature>|<$temp variable>] | 
	setpoint low [<temperature>|<$temp variable>] | setpoint high [<temperature>|<$temp variable] |
	program manual | program auto]
`
