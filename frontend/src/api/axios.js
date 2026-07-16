import axios from "axios";


const API = axios.create({

    baseURL: "http://localhost:3001/api",

    headers: {
        "Content-Type": "application/json"
    }

});



export const registerUser = (data) => {

    return API.post(
        "/auth/register",
        data
    );

};



export const loginUser = (data) => {

    return API.post(
        "/auth/login",
        data
    );

};



export const forgotPassword = (data) => {

    return API.post(
        "/auth/forgot-password",
        data
    );

};



export default API;