# Void Linux Python Update Procedure

The Void Linux `python3` package has far-reaching dependants (some people use
the term "revdeps", but I find that clumsy). Patch-level version bumps are
usually self-contained. However, updating to a new minor version---which, as of
Fall 2021, is scheduled annually---requires a rebuild of more than a thousand
packages. Anybody wishing to undertake this effort will first have to identify
all dependants, update the `python3` and `python3-tkinter` packages, make some
structural changes to `xbps-src` and then revbump the dependants. Then the
*real* fun begins: building every package for every official architecture to
check for breakage.

Past experience suggests that between 5% and 10% of the dependants will fail to
build in the first pass. Some of these failures represent existing breakage,
usually because of dependency upgrades, that had previously gone undetected.
Many will be caused by the Python update itself. A good portion of the failures
can be resolved by just updating the broken dependant, although those updates
will obviously require testing for further issues. The remaining failures will
generally require patching of the upstream package or changing build parameters
until a new release is available. Unfortunately, working through these failures
and fixes is a manual process. Fortunately, a lot of the initial effort can be
reasonably automated.

## Structural Changes to `xbps-src`

Because of Python's widespread influence, `xbps-src` requires some modification
with every minor version bump. In addition to updating the `python3` and
`python3-tkinter` packages (which must be kept synchronized!), the files
[`common/environment/setup/python.sh`](https://github.com/void-linux/void-packages/blob/master/common/environment/setup/python.sh#L10)
and
[`common/hooks/pre-configure/02-script-wrapper.sh`](https://github.com/void-linux/void-packages/blob/master/common/hooks/pre-configure/02-script-wrapper.sh#L239)
must be modified so that the referenced `3.<minor>` versions reflect the
update. Minor-version updates to Python tend also to alter the soname for the
shared library that implements the Python runtime, so remember to update
[`common/shlibs`](https://github.com/void-linux/void-packages/blob/master/common/shlibs).

Often, these three files in the `common` tree are sufficient. However, in some
cases, versioning may break recognition in other hooks. The update from `3.9`
to `3.10`, for example, required updating the shebang recognition in the hook
[`common/hooks/pre-pkg/03-rewrite-python-shebang.sh`](https://github.com/void-linux/void-packages/blob/master/common/hooks/pre-pkg/03-rewrite-python-shebang.sh#L8)
as well as version detection in the automatic byte-compilation hook
[`common/hooks/post-install/04-create-xbps-metadata-scripts.sh`](https://github.com/void-linux/void-packages/blob/master/common/hooks/post-install/04-create-xbps-metadata-scripts.sh#L269).

## Identifying and Revbumping Dependants

Normally, the `xrevshlib` command provided by the
[`xtools`](https://man.voidlinux.org/xtools.1)
package is used to identify packages that must be revbumped alongside updates
that change library sonames. This is true for Python, but Python adds
complexity because many packages install modules in the directory
`/usr/lib/python3.<minor>/site-packages`. These packages must all be rebuilt
both to test for breakage and to make sure their site-package additions end up
in the module path for the new Python version. Furthermore, several packages
include Python modules that are not installed in the central `site-packages`
directory but are configured for automatic post-installation byte-compilation.


Identifying the library dependents of `python3` is the easiest step. To dump a
list to the file `pkgs.combined`, just run, *e.g.*,
```sh
xrevshlib python3 > pkgs.combined
```

An obvious additional source of Python packages is all those whose names start
with `python3-`, so add those to the list:
```sh
(cd srcpkgs && echo python3-* | \
 xargs -n1 realpath -e | \
 xargs -n1 basename | sort | uniq) >> pkgs.combined
```
Note that the preceding command assumes you are start from the root of your
`void-packages` clone. Adjust the `cd` as necessary.

To identify a list of packages that might ship Python modules in non-standard
locations, look for those that include a `pycompile` specification (this will
generally be `pycompile_dirs`, but could be `pycompile_module`):
```sh
for f in $(grep -l pycompile srcpkgs/*/template); do
	grep -q python_version=2 $f && continue
	grep -q python_version=3 $f || grep -q python3 $f || continue
	pkg=$(xsubpkg -m $(basename ${f%/template}))
	echo $pkg >> pkgs.combined
done
```
Again, adjust the path `srcpkgs/*/template` as appropriate if this command is
run from somewhere other than the `void-packages` root.

Finally, include all packages that install files in paths matching
`usr/lib/python3`, which will capture all packages with modules in the standard
location:
```sh
xlocate usr/lib/python3 | awk '{print $1}' | sort | uniq | \
    xargs -n1 xbps-uhelper getpkgname | \
    xargs -n1 xsubpkg -m | sort | uniq >> pkgs.combined
```
If you have not used `xlocate` before, or it has been awhile since you've used
it, you should run `xlocate -S` before the preceding command or you will not
have an up-to-date list of package contents.

The resulting list of packages will probably contain duplicates. Filter the
list to remove duplicates and then let `xbps-src` order by dependencies for
later builds:
```sh
sort pkgs.combined | uniq | \
    xargs ./xbps-src sort-dependencies > pkgs.depsorted
```
After bumping the `python3` and `python3-tkinter` packages and commiting the
bumps on your working branch, revbump all of the dependants with
```sh
grep -v '^python3\(-tkinter\)\?$' pkgs.depsorted | \
    xargs xrevbump 'rebuild for Python 3.<minor>'
```
Stripping the `python3` and `python3-tkinter` package from the list, done here
with `grep`, is important to prevent needless revision bumps to the packages
you just updated.

## Automated Builds

Running through builds of all packages is important to identify breakage. The
included [`buildloop.sh`](./buildloop.sh) script provides a basic example of
how this can be automated for native and cross builds, one architecture at a
time. The script makes some attempt to be dynamic, but still hard-codes some
assumptions that will require customization. In particular, the script must be
run with the root of the `void-packages` repo as the current working directory.
It currently assumes that work is done on the `py311` git branch, although this
only substantially affects the `$REPO` variable that can be overriddent in the
environment or by setting the argument `-r $REPO`. (It also affects the default
`broken` message, but that isn't really important.) The script has a *very*
primitive check for existing packages in the local repository. If these
packages are found, the script will skip rebuilding them. This should probably
be made more robust!

To build all packages for a specific architecture, define the `$REPO_ARCH`
variable (or set the argument `-a $REPO_ARCH`) to one of the following values:
- `x86_64`
- `x86_64-musl`
- `aarch64`
- `aarch64-musl`
- `armv7l`
- `armv7l-musl`
- `armv6l`
- `armv6l-musl`
- `i686`

These represent the official Void Linux architectures for which packages are
built and distributed; other architectures may work with this script but are
not tested. The script will attempt to pick a native architecture, which will
be one of `x86_64`, `x86_64-musl`, `i686`, or `i686-musl`; any other
architecture will rely on cross-compilation. You can define `$MASTERDIR` or set
the argument `-m $MASTERDIR` to point to an `xbps-src` build root; by default,
one will be created in `/tmp`.  (If you mount a `tmpfs` at `/tmp`, this is
probably not desirable unless you have at least 64 GB of RAM; some dependants,
like `libreoffice`, can be pretty big.)

With `$REPO_ARCH` set (as well as any other appropriate environment variables),
start a build with
```sh
buildloop.sh pkgs.depsorted 2>&1 | tee -a "log.${REPO_ARCH}"
```
Note that the output is captured for easy review later. The script will happily
ignore any packages marked broken or otherwise unbuildable for an architecture.
Any unexpected failure will cause the corresponding template to be marked
broken, which allows for easy identification with the command `git status` or
`git diff --name-only`. Work through the broken templates, removing the
`broken=` line and fixing whatever is necessary for that package.

In some cases, it may be desirable to terminate a build loop when a package
fails to build rather than marking the package broken and continuing the loop.
To do so, either pass the `-x` argument to `buildloop.sh` or set the
environment variable `$PYBUMP_ERRORS_FAIL` to any non-empty value.
