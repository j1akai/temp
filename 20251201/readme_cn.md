Linux 6.18: [kernel/git/stable/linux.git](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/tag/?h=v6.18)

Configuration: [here](.config)

compiler: [gcc](gcc.log)

---

这个bug是通过模糊测试器找到的，后面我在linux的mainline(6.18)上复现成功了，内核版本、配置项清单和编译器见上面的标注。

我试着通过模糊测试器生成的[日志](report0.log)来分析这个bug的触发原因。问题应该是在fs/hfsplus/extents.c文件下，主要涉及hfsplus_get_block、hfsplus_file_extend和hfsplus_block_allocate这个函数。


日志开头说的很清楚，是在hfsplus_file_extend已经持有锁的情况下，又在hfsplus_get_block中申请锁。

```
syz.2.6665/56729 is trying to acquire lock:
ffff88803c85bdc8 (&HFSPLUS_I(inode)->extents_lock){+.+.}-{4:4}, at: hfsplus_get_block+0x27d/0xa80 fs/hfsplus/extents.c:260

but task is already holding lock:
ffff88803c85a988 (&HFSPLUS_I(inode)->extents_lock){+.+.}-{4:4}, at: hfsplus_file_extend+0x1be/0x1250 fs/hfsplus/extents.c:453
```


调用链的一部分是这样的：

```
 hfsplus_get_block+0x27d/0xa80 fs/hfsplus/extents.c:260
 block_read_full_folio+0x2f4/0x850 fs/buffer.c:2420
 filemap_read_folio+0xbf/0x2a0 mm/filemap.c:2444
 do_read_cache_folio+0x24d/0x590 mm/filemap.c:4036
 do_read_cache_page mm/filemap.c:4102 [inline]
 read_cache_page+0x5d/0x150 mm/filemap.c:4111
 read_mapping_page include/linux/pagemap.h:993 [inline]
 hfsplus_block_allocate+0x131/0xc00 fs/hfsplus/bitmap.c:37
 hfsplus_file_extend+0x439/0x1250 fs/hfsplus/extents.c:464
 hfsplus_get_block+0x1b4/0xa80 fs/hfsplus/extents.c:245
 __block_write_begin_int+0x4e5/0x1660 fs/buffer.c:2145
```

可以看到，hfsplus_get_block(fs/hfsplus/extents.c:245)会调用hfsplus_file_extend(fs/hfsplus/extents.c:464)，在hfsplus_file_extend中会申请锁，而后调用hfsplus_block_allocate(如下面代码所示)。

```
int hfsplus_file_extend(struct inode *inode, bool zeroout)
{
	...
	mutex_lock(&hip->extents_lock);
	...

	start = hfsplus_block_allocate(sb, sbi->total_blocks, goal, &len);
	...
}
```

在当前线程已经持有锁的情况下，hfsplus_block_allocate会调用到hfsplus_get_block(fs/hfsplus/extents.c:260)，而此时hfsplus_get_block会尝试申请已经持有的锁，这导致了死锁。


为了解决上面的问题，我做了一个比较简单的修改，即在hfsplus_file_extend调用hfsplus_block_allocate之前释放锁，然后在hfsplus_block_allocate返回后重新申请锁，如下：

```
int hfsplus_file_extend(struct inode *inode, bool zeroout)
{
	...
	mutex_unlock(&hip->extents_lock);

	len = hip->clump_blocks;
	start = hfsplus_block_allocate(sb, sbi->total_blocks, goal, &len);

	mutex_lock(&hip->extents_lock);
	...
}
```

但是这样不行，会有同类的其他错误，见[日志](fix.log)。


或许另一种方法是改变hfsplus_inode_info中extents_lock的数据结构？不过这涉及较多修改的代码，所以我还没有做尝试。


以上是我的一些分析，希望能有一点用。
