class PerconaServer < Formula
  desc "Drop-in MySQL replacement"
  homepage "https://www.percona.com"
  url "https://downloads.percona.com/downloads/Percona-Server-8.0/Percona-Server-8.0.28-20/source/tarball/percona-server-8.0.28-20.tar.gz"
  sha256 "88890e081d70901f938e39b688663d4514910773488fca42cd6de0f4371fb157"
  license "BSD-3-Clause"
  revision 1

  livecheck do
    url "https://www.percona.com/downloads/Percona-Server-LATEST/"
    regex(/value=.*?Percona-Server[._-]v?(\d+(?:\.\d+)+-\d+)["' >]/i)
  end

  bottle do
    sha256 arm64_monterey: "c9e4666a211c4518fb8ec476d31787a7444052eee170f795c9627827c63ed340"
    sha256 arm64_big_sur:  "f0053fa76ffddda44648fc661b4b78598adbd56d6f0b8da44bc87b264edceae4"
    sha256 monterey:       "ad7bc723035a9751aaf5759dcaa145d946edb804af2e5b912416035a2e6e2d81"
    sha256 big_sur:        "64073166682704e24987ab8a0fb0390e8dd69b63beddb4522f68c0c6555be1f1"
    sha256 catalina:       "d39e4d11773084c919425316bdad2d58fdf2bca38b56103376e48c926a31b170"
    sha256 x86_64_linux:   "36eb30e92549e3277d3792a27f3f4ec44123f519e653a7bb8e804967861eff89"
  end

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build
  depends_on "icu4c"
  depends_on "libevent"
  depends_on "libfido2"
  depends_on "lz4"
  depends_on "openssl@1.1"
  depends_on "protobuf"
  depends_on "zstd"

  uses_from_macos "curl"
  uses_from_macos "cyrus-sasl"
  uses_from_macos "libedit"
  uses_from_macos "openldap"
  uses_from_macos "zlib"

  on_linux do
    depends_on "patchelf" => :build
    depends_on "gcc"
    depends_on "readline"

    # Fix build with OpenLDAP 2.5+, which merged libldap_r into libldap
    patch :DATA
  end

  conflicts_with "mariadb", "mysql", because: "percona, mariadb, and mysql install the same binaries"
  conflicts_with "percona-xtrabackup", because: "both install a `kmip.h`"

  # https://bugs.mysql.com/bug.php?id=86711
  # https://github.com/Homebrew/homebrew-core/pull/20538
  fails_with :clang do
    build 800
    cause "Wrong inlining with Clang 8.0, see MySQL Bug #86711"
  end

  fails_with :gcc do
    version "6"
    cause "GCC 7.1 or newer is required"
  end

  # https://github.com/percona/percona-server/blob/Percona-Server-#{version}/cmake/boost.cmake
  resource "boost" do
    url "https://boostorg.jfrog.io/artifactory/main/release/1.73.0/source/boost_1_73_0.tar.bz2"
    sha256 "4eb3b8d442b426dc35346235c8733b5ae35ba431690e38c6a8263dce9fcbb402"
  end

  # Fix libfibo2 finding; fix unneeded copying of openssl@1.1 libs
  # Remove in the next version (8.0.29)
  patch do
    url "https://raw.githubusercontent.com/Homebrew/formula-patches/3e668c9996eef41f7d7fa4e2d647f2b80da699e1/percona-server/8.0.28-19.diff"
    sha256 "1410c30b8634c2bb011de08a45ea2b2c7edce13b846871a8447658c1c262ddbf"
  end

  def install
    # Fix mysqlrouter_passwd RPATH to link to metadata_cache.so
    inreplace "router/src/http/src/CMakeLists.txt",
              "ADD_INSTALL_RPATH(mysqlrouter_passwd \"${ROUTER_INSTALL_RPATH}\")",
              "\\0\nADD_INSTALL_RPATH(mysqlrouter_passwd \"${RPATH_ORIGIN}/../${ROUTER_INSTALL_PLUGINDIR}\")"

    # Disable ABI checking
    inreplace "cmake/abi_check.cmake", "RUN_ABI_CHECK 1", "RUN_ABI_CHECK 0" if OS.linux?

    # -DINSTALL_* are relative to `CMAKE_INSTALL_PREFIX` (`prefix`)
    args = %W[
      -DFORCE_INSOURCE_BUILD=1
      -DCOMPILATION_COMMENT=Homebrew
      -DDEFAULT_CHARSET=utf8mb4
      -DDEFAULT_COLLATION=utf8mb4_0900_ai_ci
      -DINSTALL_DOCDIR=share/doc/#{name}
      -DINSTALL_INCLUDEDIR=include/mysql
      -DINSTALL_INFODIR=share/info
      -DINSTALL_MANDIR=share/man
      -DINSTALL_MYSQLSHAREDIR=share/mysql
      -DINSTALL_PLUGINDIR=lib/percona-server/plugin
      -DMYSQL_DATADIR=#{var}/mysql
      -DSYSCONFDIR=#{etc}
      -DENABLED_LOCAL_INFILE=1
      -DWITH_EMBEDDED_SERVER=ON
      -DWITH_INNODB_MEMCACHED=ON
      -DWITH_UNIT_TESTS=OFF
      -DWITH_SYSTEM_LIBS=ON
      -DWITH_EDITLINE=system
      -DWITH_FIDO=system
      -DWITH_ICU=system
      -DWITH_LIBEVENT=system
      -DWITH_LZ4=system
      -DWITH_PROTOBUF=system
      -DWITH_SSL=system
      -DOPENSSL_ROOT_DIR=#{Formula["openssl@1.1"].opt_prefix}
      -DWITH_ZLIB=system
      -DWITH_ZSTD=system
    ]

    # MySQL >5.7.x mandates Boost as a requirement to build & has a strict
    # version check in place to ensure it only builds against expected release.
    # This is problematic when Boost releases don't align with MySQL releases.
    (buildpath/"boost").install resource("boost")
    args << "-DWITH_BOOST=#{buildpath}/boost"

    # Percona MyRocks does not compile on macOS
    # https://bugs.launchpad.net/percona-server/+bug/1741639
    args.concat %w[-DWITHOUT_ROCKSDB=1]

    # TokuDB does not compile on macOS
    # https://bugs.launchpad.net/percona-server/+bug/1531446
    args.concat %w[-DWITHOUT_TOKUDB=1]

    system "cmake", ".", *std_cmake_args, *args
    system "make"
    system "make", "install"

    (prefix/"mysql-test").cd do
      test_args = ["--vardir=#{Dir.mktmpdir}"]
      # For Linux, disable failing on warning: "Setting thread 31563 nice to 0 failed"
      # Docker containers lack CAP_SYS_NICE capability by default.
      test_args << "--nowarnings" if OS.linux?
      system "./mysql-test-run.pl", "status", *test_args
    end

    # Remove the tests directory
    rm_rf prefix/"mysql-test"

    # Don't create databases inside of the prefix!
    # See: https://github.com/Homebrew/homebrew/issues/4975
    rm_rf prefix/"data"

    # Fix up the control script and link into bin.
    inreplace "#{prefix}/support-files/mysql.server",
              /^(PATH=".*)(")/,
              "\\1:#{HOMEBREW_PREFIX}/bin\\2"
    bin.install_symlink prefix/"support-files/mysql.server"

    # Install my.cnf that binds to 127.0.0.1 by default
    (buildpath/"my.cnf").write <<~EOS
      # Default Homebrew MySQL server config
      [mysqld]
      # Only allow connections from localhost
      bind-address = 127.0.0.1
    EOS
    etc.install "my.cnf"
  end

  def post_install
    # Make sure the var/mysql directory exists
    (var/"mysql").mkpath

    # Don't initialize database, it clashes when testing other MySQL-like implementations.
    return if ENV["HOMEBREW_GITHUB_ACTIONS"]

    unless (var/"mysql/mysql/user.frm").exist?
      ENV["TMPDIR"] = nil
      system bin/"mysqld", "--initialize-insecure", "--user=#{ENV["USER"]}",
        "--basedir=#{prefix}", "--datadir=#{var}/mysql", "--tmpdir=/tmp"
    end
  end

  def caveats
    s = <<~EOS
      We've installed your MySQL database without a root password. To secure it run:
          mysql_secure_installation
      MySQL is configured to only allow connections from localhost by default
      To connect run:
          mysql -uroot
    EOS
    if (my_cnf = ["/etc/my.cnf", "/etc/mysql/my.cnf"].find { |x| File.exist? x })
      s += <<~EOS
        A "#{my_cnf}" from another install may interfere with a Homebrew-built
        server starting up correctly.
      EOS
    end
    s
  end

  service do
    run [opt_bin/"mysqld_safe", "--datadir=#{var}/mysql"]
    keep_alive true
    working_dir var/"mysql"
  end

  test do
    (testpath/"mysql").mkpath
    (testpath/"tmp").mkpath
    system bin/"mysqld", "--no-defaults", "--initialize-insecure", "--user=#{ENV["USER"]}",
      "--basedir=#{prefix}", "--datadir=#{testpath}/mysql", "--tmpdir=#{testpath}/tmp"
    port = free_port
    fork do
      system "#{bin}/mysqld", "--no-defaults", "--user=#{ENV["USER"]}",
        "--datadir=#{testpath}/mysql", "--port=#{port}", "--tmpdir=#{testpath}/tmp"
    end
    sleep 5
    assert_match "information_schema",
      shell_output("#{bin}/mysql --port=#{port} --user=root --password= --execute='show databases;'")
    system "#{bin}/mysqladmin", "--port=#{port}", "--user=root", "--password=", "shutdown"
  end
end

__END__
--- a/plugin/auth_ldap/CMakeLists.txt
+++ b/plugin/auth_ldap/CMakeLists.txt
@@ -36,7 +36,7 @@ IF(WITH_LDAP)

   # libler?
   MYSQL_ADD_PLUGIN(authentication_ldap_simple ${ALP_SOURCES_SIMPLE}
-    LINK_LIBRARIES ldap_r MODULE_ONLY MODULE_OUTPUT_NAME "authentication_ldap_simple")
+    LINK_LIBRARIES ldap MODULE_ONLY MODULE_OUTPUT_NAME "authentication_ldap_simple")

   IF(UNIX)
     IF(INSTALL_MYSQLTESTDIR)
