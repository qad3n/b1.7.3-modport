# b1.7.3-modport

A Claude Code skill and a few scripts for porting Minecraft Java mods to the
[b1.7.3-rewrite](https://github.com/qad3n/b1.7.3-rust-rewrite) mod loader. A port is a Rust rewrite of the mod that
builds to one `.b173mod` file for both client and server.

## Setup

Put this repo and the rewrite side by side in one folder:

```bash
git clone --recurse-submodules https://github.com/qad3n/b1.7.3-rust-rewrite.git b1.7.3-rewrite
git clone https://github.com/qad3n/b1.7.3-modport.git
./b1.7.3-modport/install.sh
```

`install.sh` links the skill and tools into the folder and checks what is missing. Each missing item comes with the
command that fixes it.

## Use

Open Claude Code in that folder and run `/modport` with a mod jar. The scripts in `tools/` also work by hand:

- `new_port.sh <modid> <jar>` starts a port in `ports/<modid>`
- `test.sh deploy ports/<modid>` builds it and runs it on a test server
- `doctor.sh` checks the setup again

No game or mod assets are included. They come from jars you own.

## License

Non-commercial, see [LICENSE](LICENSE).
