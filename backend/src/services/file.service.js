const fs = require("fs");
const path = require("path");



function deleteFile(filePath) {


    const absolute =
        path.join(
            process.cwd(),
            filePath
        );


    if (fs.existsSync(absolute)) {

        fs.unlinkSync(
            absolute
        );

    }

}



function getFilePath(file) {

    return file.path
        .replace(
            process.cwd(),
            ""
        )
        .replace(
            /\\/g,
            "/"
        )
        .substring(1);


}



module.exports = {
    deleteFile,
    getFilePath
};