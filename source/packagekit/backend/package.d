/*
 * SPDX-FileCopyrightText: Copyright © 2023 Ikey Doherty
 *
 * SPDX-License-Identifier: Zlib
 */

/**
 * packagekit.backend
 *
 * PackageKit plugin for deopkg API
 * Exposes a C API to match https://github.com/PackageKit/PackageKit/blob/main/src/pk-backend.c#L494
 *
 * This module is split across multiple files to make the implementation simpler and group by logical
 * functionality.
 *
 * Authors: Copyright © 2023 Ikey Doherty
 * License: Zlib
 */

module packagekit.backend;

@safe:

import glib.c.functions : g_strdupv, g_strv_length;
import glib.c.types : GKeyFile;
import packagekit.bitfield;
import packagekit.enums;
import packagekit.job;
import pyd.embedded;
import pyd.pyd;
import std.meta;
import std.stdint : uint64_t;
import std.traits;

public import packagekit.backend.deps;
public import packagekit.backend.download;
public import packagekit.backend.files;
public import packagekit.backend.info;
public import packagekit.backend.install;
public import packagekit.backend.jobs;
public import packagekit.backend.list;
public import packagekit.backend.lookup;
public import packagekit.backend.refresh;
public import packagekit.backend.remove;
public import packagekit.backend.repos;
public import packagekit.backend.search;
public import packagekit.backend.updates;

private static immutable char*[] mimeTypes = [null];

/**
 * Handle python teardown in dtor
 */
shared static ~this() @trusted
{
    py_finish();
}

export extern (C)
{
    struct PkBackend;

    /** 
     * Params:
     *   self = Current backend
     * Returns: backend author
     */
    const(char*) pk_backend_get_author(PkBackend* self) => "Ikey Doherty";

    /** 
     * Params:
     *   self = Current backend
     * Returns: backend name
     */
    const(char*) pk_backend_get_name(PkBackend* self) => "deopkg";

    /** 
     * Params:
     *   self = Current backend
     * Returns: backend description
     */
    const(char*) pk_backend_get_description(PkBackend* self) => "eopkg support";

    /** 
     * Initialise the backend
     *
     * Params:
     *   config = PackageKit's configuration file
     *   self = Current backend
     */
    void pk_backend_initialize(GKeyFile* config, PkBackend* self) @trusted
    {
        imported!"core.stdc.stdio".puts("[deopkg] Init\n");
        on_py_init({ add_module!(ModuleName!"deopkg"); });
        py_init();

        // Prove that we can "get" packages
        import std.algorithm : each;
        import std.stdio : writeln;

        alias py_def!(import("getPackages.py"), "deopkg", string[]function()) getPackages;
        getPackages.each!writeln;
    }

    /** 
     * Destroy the backend
     *
     * Params:  
     *   self = Current backend
     */
    void pk_backend_destroy(PkBackend* self) @trusted
    {
        imported!"core.stdc.stdio".puts("[deopkg] Destroy\n");
    }

    /** 
     * Notify the daemon of the supported groups. We hard-code as supporting
     * all of them.
     *
     * Params:
     *   self = Current backend
     * Returns: Supported groups for enumeration
     */
    PkBitfield pk_backend_get_groups(PkBackend* self)
    {
        static PkBitfield groups;

        groups = 0;
        static foreach (group; cast(PkGroupEnum) 1 .. PkGroupEnum.PK_GROUP_ENUM_LAST)
        {
            groups = pk_bitfield_add(groups, group);
        }

        return groups;
    }

    /** 
     * Exposes all of our supported roles.
     *
     * We explicitly do not support EULA, cancelation or showing old transactions atm.
     *
     * Params:
     *   self = Current backend
     * Returns: Supported roles (APIs)
     */
    PkBitfield pk_backend_get_roles(PkBackend* self)
    {
        template RoleFilter(PkRoleEnum n)
        {
            import std.algorithm : among;

            enum RoleFilter = !n.among(PkRoleEnum.PK_ROLE_ENUM_UNKNOWN, PkRoleEnum.PK_ROLE_ENUM_ACCEPT_EULA,
                        PkRoleEnum.PK_ROLE_ENUM_CANCEL,
                        PkRoleEnum.PK_ROLE_ENUM_GET_OLD_TRANSACTIONS);
        }

        static roles = Filter!(RoleFilter, EnumMembers!PkRoleEnum);
        return pk_bitfield_from_enums(roles);
    }

    /** 
     * Exposes all of our supported filters
     *
     * Params:
     *   self = Current backend
     * Returns: Supported filters
     */
    PkBitfield pk_backend_get_filters(PkBackend* self)
    {
        with (PkFilterEnum)
        {
            return pk_bitfield_from_enums(PK_FILTER_ENUM_DEVELOPMENT,
                    PK_FILTER_ENUM_GUI, PK_FILTER_ENUM_INSTALLED,);
        }
    }

    PkBitfield pk_backend_get_provides(PkBackend* self) => 0;

    /** 
     * Params:
     *   self = Current backend
     * Returns: An allocated copy of supported mimetypes
     */
    char** pk_backend_get_mime_types(PkBackend* self) @trusted => (cast(char**) mimeTypes.ptr)
        .g_strdupv;

    /** 
     * We don't yet support threaded usage.
     * Params:
     *   self = Current backend
     * Returns: False. Always.
     */
    bool pk_backend_supports_parallelization(PkBackend* self) => false;

    /* NOT SUPPORTED */
    void pk_backend_repair_system(PkBackend* backend, PkBackendJob* job,
            PkBitfield transactionFlags)
    {
        pk_backend_job_finished(job);
    }
}
