import hashlib,importlib.util,io,tarfile,tempfile,unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('original_media',Path(__file__).parents[1]/'install-original-media.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class OriginalMediaTest(unittest.TestCase):
 def test_content_addressed_stage_is_idempotent(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);payload=b'owned-test-bytes';h=hashlib.sha256(payload).hexdigest();archive=root/'a.tgz'
   with tarfile.open(archive,'w:gz') as tar:
    member=tarfile.TarInfo('audio.'+h+'.wav');member.size=len(payload);tar.addfile(member,io.BytesIO(payload))
   digest=module.digest(archive)
   self.assertEqual(module.stage(archive,digest,root/'objects'),(1,len(payload)))
   self.assertEqual(module.stage(archive,digest,root/'objects'),(1,len(payload)))
   self.assertEqual((root/'objects'/member.name).read_bytes(),payload)
 def test_path_and_symlink_members_are_rejected(self):
  for kind in ['path','symlink']:
   with self.subTest(kind=kind),tempfile.TemporaryDirectory() as folder:
    root=Path(folder);archive=root/'bad.tgz'
    with tarfile.open(archive,'w:gz') as tar:
     member=tarfile.TarInfo('../escape' if kind=='path' else 'audio.'+'a'*64+'.wav')
     if kind=='symlink':member.type=tarfile.SYMTYPE;member.linkname='/etc/passwd'
     tar.addfile(member)
    with self.assertRaises(ValueError):module.stage(archive,module.digest(archive),root/'objects')
    self.assertFalse((root/'escape').exists())
 def test_bad_transport_hash_cannot_stage_bytes(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);archive=root/'a.tgz';archive.write_bytes(b'not-an-archive')
   with self.assertRaises(ValueError):module.stage(archive,'a'*64,root/'objects')
   self.assertFalse((root/'objects').exists())
if __name__=='__main__':unittest.main()
